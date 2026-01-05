module PipeChannels

export PipeChannel

"""
    PipeChannel{T}

A lock-free single-producer single-consumer channel using a ring buffer.

This implementation uses atomic operations for the head and tail indices,
allowing one thread to write and another to read without any locks.
This eliminates allocations in the hot path that would otherwise occur
with Julia's Channel type.

The API matches Julia's `Channel`:
- `put!` blocks when full, throws `InvalidStateException` when closed
- `take!` blocks when empty, throws `InvalidStateException` when closed and empty
- Iteration works with `for x in ch` syntax
- `bind` connects a task to the channel for error propagation

# Type Parameters
- `T`: Element type stored in the channel

# Fields
- `buffer::Vector{T}`: Pre-allocated storage
- `capacity::Int`: Maximum number of elements (one slot reserved for full/empty detection)
- `head::Threads.Atomic{Int}`: Write position (modified only by producer)
- `tail::Threads.Atomic{Int}`: Read position (modified only by consumer)

# Thread Safety
- Exactly ONE producer thread may call `put!`
- Exactly ONE consumer thread may call `take!`
- Multiple producers or consumers will cause data races

# Examples
```julia
ch = PipeChannel{Int}(16)

# Producer thread
put!(ch, 42)
close(ch)

# Consumer thread
value = take!(ch)  # Returns 42
take!(ch)  # Throws InvalidStateException (closed and empty)
```
"""
mutable struct PipeChannel{T} <: AbstractChannel{T}
    buffer::Vector{T}
    capacity::Int
    head::Threads.Atomic{Int}  # Write position (producer only)
    tail::Threads.Atomic{Int}  # Read position (consumer only)
    closed::Threads.Atomic{Bool}
    excp::Union{Exception,Nothing}  # Exception from bound task

    function PipeChannel{T}(capacity::Integer) where {T}
        capacity > 0 || throw(ArgumentError("Capacity must be positive"))
        # Allocate one extra slot to distinguish full from empty
        buffer = Vector{T}(undef, capacity + 1)
        return new{T}(buffer, capacity + 1, Threads.Atomic{Int}(1), Threads.Atomic{Int}(1), Threads.Atomic{Bool}(false), nothing)
    end
end

"""
    isopen(ch::PipeChannel) -> Bool

Check if the channel is still open for operations.
"""
Base.isopen(ch::PipeChannel) = !ch.closed[]

"""
    close(ch::PipeChannel, excp::Exception=closed_exception())

Close the channel. After closing:
- `put!` will throw `InvalidStateException` (or the bound task's exception)
- `take!` will return remaining elements, then throw `InvalidStateException` (or the bound task's exception)

If `excp` is provided, it will be stored and thrown on subsequent operations.
"""
function Base.close(ch::PipeChannel, excp::Exception=Base.closed_exception())
    ch.excp = excp
    ch.closed[] = true
    return nothing
end

# Helper to throw the appropriate exception
function check_closed_and_throw(ch::PipeChannel)
    if ch.excp !== nothing && !isa(ch.excp, InvalidStateException)
        throw(ch.excp)
    end
    throw(InvalidStateException("PipeChannel is closed.", :closed))
end

"""
    bind(ch::PipeChannel, task::Task)

Bind a task to the channel. When the task terminates:
- The channel is automatically closed
- If the task failed with an exception, that exception will be thrown
  on subsequent `put!` or `take!` operations

This is useful for propagating errors from producer/consumer tasks.

# Examples
```julia
ch = PipeChannel{Int}(16)
task = @async begin
    for i in 1:10
        put!(ch, i)
    end
    close(ch)
end
bind(ch, task)

# If task fails, the exception propagates to consumers
for x in ch
    println(x)
end
```
"""
function Base.bind(ch::PipeChannel, task::Task)
    # Register a callback that runs when the task completes
    @async begin
        try
            wait(task)
        catch
            # Task failed - will be handled below
        end
        # Close the buffer when task completes
        if istaskfailed(task)
            close(ch, TaskFailedException(task))
        elseif !ch.closed[]
            close(ch)
        end
    end
    return nothing
end

"""
    isfull(ch::PipeChannel) -> Bool

Check if the buffer is full.

# Thread Safety Note

This function is only guaranteed to be accurate when called from the **producer thread**.

The result can be a false positive (reports full when not full) if called from the consumer
thread, because the consumer may have advanced `tail` after we read it but before we compare.
This is safe - it just means the producer might unnecessarily wait.

However, if the producer calls this and it returns `false`, it is guaranteed that there is
space to write, because only the producer advances `head` and only the consumer advances `tail`
(which can only create more space, not less).
"""
function Base.isfull(ch::PipeChannel)
    head = ch.head[]
    tail = ch.tail[]
    next_head = head == ch.capacity ? 1 : head + 1
    return next_head == tail
end

"""
    isempty(ch::PipeChannel) -> Bool

Check if the buffer is empty.

# Thread Safety Note

This function is only guaranteed to be accurate when called from the **consumer thread**.

The result can be a false positive (reports empty when not empty) if called from the producer
thread, because the producer may have advanced `head` after we read it but before we compare.
This is safe - it just means the consumer might unnecessarily wait.

However, if the consumer calls this and it returns `false`, it is guaranteed that there is
data to read, because only the consumer advances `tail` and only the producer advances `head`
(which can only add more data, not remove it).
"""
function Base.isempty(ch::PipeChannel)
    return ch.head[] == ch.tail[]
end

"""
    isready(ch::PipeChannel) -> Bool

Check if data is available to read (i.e., buffer is not empty).

This is the opposite of `isempty` and matches the `Channel` API where
`isready(ch)` returns `true` when `take!` would not block.

# Thread Safety Note

Same as `isempty`: only guaranteed accurate from the consumer thread.
May return `false` even when data is available if called from the producer
thread (false negative is safe - just causes unnecessary waiting).
"""
Base.isready(ch::PipeChannel) = !isempty(ch)

"""
    wait(ch::PipeChannel)

Block until data is available in the buffer or the channel is closed.

Unlike `take!`, this does not consume the data - it just waits until
`isready(ch)` would return `true`, or throws if the channel is closed and empty.

# Throws
- `InvalidStateException`: If the channel is closed and empty
- The bound task's exception if the task failed

# Thread Safety
Should only be called from the consumer thread.
"""
function Base.wait(ch::PipeChannel)
    while true
        # Check if data is available
        if ch.head[] != ch.tail[]
            return nothing
        end
        # Check if closed and empty
        if ch.closed[]
            check_closed_and_throw(ch)
        end
        # Spin-wait
        yield()
    end
end

"""
    n_avail(ch::PipeChannel) -> Int

Return the number of elements available to read.

# Thread Safety Note

This is an approximation that may be slightly stale. The actual count may be higher
(if the producer added items after we read `head`) but never lower (the consumer is
the only one who can remove items by advancing `tail`).

Most accurate when called from the consumer thread.
"""
function Base.n_avail(ch::PipeChannel)
    head = ch.head[]
    tail = ch.tail[]
    if head >= tail
        return head - tail
    else
        return ch.capacity - tail + head
    end
end

"""
    put!(ch::PipeChannel{T}, value::T)

Add an element to the buffer. Blocks if the buffer is full.

# Throws
- `InvalidStateException`: If the channel is closed
- The bound task's exception if the task failed

# Thread Safety
Must only be called from a single producer thread.
"""
function Base.put!(ch::PipeChannel{T}, value::T) where {T}
    while true
        if ch.closed[]
            check_closed_and_throw(ch)
        end

        head = ch.head[]
        next_head = head == ch.capacity ? 1 : head + 1

        # Check if buffer is full - spin-wait
        if next_head == ch.tail[]
            yield()
            continue
        end

        # Write the value
        @inbounds ch.buffer[head] = value

        # Publish the write by advancing head
        ch.head[] = next_head

        return value
    end
end

"""
    take!(ch::PipeChannel{T}) -> T

Remove and return an element from the buffer. Blocks if the buffer is empty.

# Throws
- `InvalidStateException`: If the channel is closed and empty
- The bound task's exception if the task failed

# Thread Safety
Must only be called from a single consumer thread.
"""
function Base.take!(ch::PipeChannel{T}) where {T}
    while true
        tail = ch.tail[]
        head = ch.head[]

        # Check if buffer is empty
        if tail == head
            if ch.closed[]
                check_closed_and_throw(ch)
            end
            # Spin-wait
            yield()
            continue
        end

        # Read the value
        @inbounds value = ch.buffer[tail]

        # Advance tail
        next_tail = tail == ch.capacity ? 1 : tail + 1
        ch.tail[] = next_tail

        return value
    end
end

"""
    iterate(ch::PipeChannel{T}, state=nothing)

Iterate over values in the channel until it's closed and empty.
Catches `InvalidStateException` to cleanly end iteration.
If a bound task failed, the `TaskFailedException` is propagated.

Note: The `@inline` annotation is critical for avoiding heap allocation of the
returned `(value, nothing)` tuple when `T` is not an isbits type.
"""
@inline function Base.iterate(ch::PipeChannel{T}, state=nothing) where {T}
    try
        value = take!(ch)
        return (value, nothing)
    catch e
        if e isa InvalidStateException
            return nothing
        end
        rethrow()
    end
end

"""
    IteratorSize(::Type{<:PipeChannel})

Returns `Base.SizeUnknown()` since the number of elements in a `PipeChannel`
cannot be determined in advance (depends on when the channel is closed).
"""
Base.IteratorSize(::Type{<:PipeChannel}) = Base.SizeUnknown()

"""
    eltype(::Type{PipeChannel{T}}) where T

Returns the element type `T` of the `PipeChannel{T}`.
"""
Base.eltype(::Type{PipeChannel{T}}) where {T} = T

# ============================================================================
# Batch Operations
# ============================================================================

"""
    put!(ch::PipeChannel{T}, values::AbstractVector{T}) -> AbstractVector{T}

Add multiple elements to the buffer in a single batch operation.
Blocks until all items are written. Returns the input vector.

This is more efficient than calling `put!` repeatedly because:
- Fewer atomic writes (one per batch of items that fit)
- Reduced per-item overhead

# Behavior
- Writes as many items as possible, then blocks until space is available
- Continues until all items are written
- Returns the input vector (for consistency with single-item `put!`)

# Throws
- `InvalidStateException`: If the channel is closed

# Thread Safety
Must only be called from a single producer thread.

# Examples
```julia
ch = PipeChannel{Int}(100)
data = collect(1:50)
put!(ch, data)  # Blocks until all 50 items are written
```
"""
function Base.put!(ch::PipeChannel{T}, values::AbstractVector{T}) where {T}
    isempty(values) && return values

    offset = 0
    total = length(values)

    while offset < total
        if ch.closed[]
            check_closed_and_throw(ch)
        end

        head = ch.head[]
        tail = ch.tail[]

        # Calculate available space
        if head >= tail
            # Available space is split: from head to capacity, and from 1 to tail-1
            space_to_end = ch.capacity - head + 1
            space_at_start = tail - 1
            total_space = space_to_end + space_at_start - 1  # -1 because we can't fill completely
        else
            # Available space is contiguous: from head to tail-1
            total_space = tail - head - 1
        end

        # No space available - spin-wait
        if total_space <= 0
            yield()
            continue
        end

        # Write as many items as we can
        n_to_write = min(total - offset, total_space)

        pos = head
        @inbounds for i in 1:n_to_write
            ch.buffer[pos] = values[offset + i]
            pos = pos == ch.capacity ? 1 : pos + 1
        end

        # Single atomic update to publish all writes
        ch.head[] = pos
        offset += n_to_write
    end

    return values
end

"""
    take!(ch::PipeChannel{T}, n::Integer) -> Vector{T}

Remove and return exactly `n` elements from the buffer in a single batch operation.
Blocks until all `n` items are available.

This is more efficient than calling `take!` repeatedly because:
- Fewer atomic writes (one per batch of items available)
- Single allocation for the result vector
- Reduced per-item overhead

# Behavior
- Reads as many items as available, then blocks until more data arrives
- Continues until exactly `n` items are read
- Returns a vector of exactly `n` items

# Throws
- `InvalidStateException`: If the channel is closed before `n` items can be read

# Thread Safety
Must only be called from a single consumer thread.

# Examples
```julia
ch = PipeChannel{Int}(100)
# ... producer puts data ...
batch = take!(ch, 32)  # Blocks until exactly 32 items are available
```
"""
function Base.take!(ch::PipeChannel{T}, n::Integer) where {T}
    n <= 0 && return T[]
    result = Vector{T}(undef, n)
    take!(ch, result)
    return result
end

"""
    take!(ch::PipeChannel{T}, output::AbstractVector{T}) -> Int

Remove elements from the buffer into a pre-allocated output vector.
Blocks until the entire output buffer is filled. Returns `length(output)`.

This variant avoids allocation by writing into a provided buffer.

# Behavior
- Reads as many items as available, then blocks until more data arrives
- Continues until the entire output buffer is filled
- Returns `length(output)`

# Throws
- `InvalidStateException`: If the channel is closed before the buffer can be filled

# Thread Safety
Must only be called from a single consumer thread.

# Examples
```julia
ch = PipeChannel{Int}(100)
buffer = Vector{Int}(undef, 32)
take!(ch, buffer)  # Blocks until all 32 slots are filled
```
"""
function Base.take!(ch::PipeChannel{T}, output::AbstractVector{T}) where {T}
    isempty(output) && return 0

    total = length(output)
    offset = 0

    while offset < total
        tail = ch.tail[]
        head = ch.head[]

        # Check if buffer is empty
        if tail == head
            if ch.closed[]
                check_closed_and_throw(ch)
            end
            # Spin-wait for data
            yield()
            continue
        end

        # Calculate available items
        if head >= tail
            available = head - tail
        else
            available = ch.capacity - tail + head
        end

        # Read as many items as we can
        n_to_read = min(total - offset, available)

        pos = tail
        @inbounds for i in 1:n_to_read
            output[offset + i] = ch.buffer[pos]
            pos = pos == ch.capacity ? 1 : pos + 1
        end

        # Single atomic update to release all read slots
        ch.tail[] = pos
        offset += n_to_read
    end

    return total
end

end # module PipeChannels
