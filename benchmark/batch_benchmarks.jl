using BenchmarkTools
using PipeChannels

# Number of items to push through the channel per benchmark iteration
const BATCH_NUM_ITEMS = 10_000

# Batch sizes to test
const BATCH_SIZES = [8, 16, 32, 64, 128, 256]

# Buffer size for batch benchmarks (should be >= largest batch size)
const BATCH_BUFFER_SIZE = 1024

SUITE["batch"] = BenchmarkGroup()

# ============================================================================
# Throughput benchmarks: compare single vs batch operations
# ============================================================================

# Single operations baseline (same as pipechannel throughput)
function setup_batch_single()
    ch = PipeChannel{Int}(BATCH_BUFFER_SIZE)
    return ch
end

function run_batch_single!(ch::PipeChannel{Int}, num_items::Int)
    producer = Threads.@spawn begin
        for i in 1:num_items
            put!(ch, i)
        end
        close(ch)
    end

    consumer = Threads.@spawn begin
        for _ in ch
            # discard
        end
    end

    wait(producer)
    wait(consumer)
    return nothing
end

SUITE["batch"]["single"] = @benchmarkable(
    run_batch_single!(ch, BATCH_NUM_ITEMS),
    setup = (ch = setup_batch_single()),
    evals = 1
)

# Batch operations with various batch sizes
function setup_batch_throughput()
    ch = PipeChannel{Int}(BATCH_BUFFER_SIZE)
    return ch
end

function run_batch_throughput!(ch::PipeChannel{Int}, num_items::Int, batch_size::Int)
    producer = Threads.@spawn begin
        data = Vector{Int}(undef, batch_size)
        i = 1
        while i <= num_items
            batch_end = min(i + batch_size - 1, num_items)
            batch_len = batch_end - i + 1
            for j in 1:batch_len
                data[j] = i + j - 1
            end
            put!(ch, @view data[1:batch_len])
            i = batch_end + 1
        end
        close(ch)
    end

    consumer = Threads.@spawn begin
        count = 0
        buffer = Vector{Int}(undef, batch_size)
        while count < num_items && isopen(ch)
            remaining = num_items - count
            batch_len = min(batch_size, remaining)
            try
                take!(ch, @view buffer[1:batch_len])
                count += batch_len
            catch e
                e isa InvalidStateException || rethrow()
                break
            end
        end
    end

    wait(producer)
    wait(consumer)
    return nothing
end

for batch_size in BATCH_SIZES
    SUITE["batch"]["batch=$batch_size"] = @benchmarkable(
        run_batch_throughput!(ch, BATCH_NUM_ITEMS, $batch_size),
        setup = (ch = setup_batch_throughput()),
        evals = 1
    )
end

# ============================================================================
# Individual operation benchmarks: batch put! and take!
# ============================================================================

# Batch put! benchmark
function setup_batch_put(batch_size::Int)
    ch = PipeChannel{Int}(BATCH_BUFFER_SIZE)
    data = collect(1:batch_size)
    return (ch, data)
end

for batch_size in BATCH_SIZES
    SUITE["batch"]["put!_batch=$batch_size"] = @benchmarkable(
        put!(ch, data),
        setup = ((ch, data) = setup_batch_put($batch_size)),
        teardown = (close(ch))
    )
end

# Batch take! benchmark (with count)
function setup_batch_take(batch_size::Int)
    ch = PipeChannel{Int}(BATCH_BUFFER_SIZE)
    # Fill with enough items for multiple takes
    for i in 1:BATCH_BUFFER_SIZE
        put!(ch, i)
    end
    return ch
end

for batch_size in BATCH_SIZES
    SUITE["batch"]["take!_batch=$batch_size"] = @benchmarkable(
        take!(ch, $batch_size),
        setup = (ch = setup_batch_take($batch_size)),
        teardown = (close(ch))
    )
end

# Batch take! into pre-allocated buffer
function setup_batch_take_buffer(batch_size::Int)
    ch = PipeChannel{Int}(BATCH_BUFFER_SIZE)
    for i in 1:BATCH_BUFFER_SIZE
        put!(ch, i)
    end
    buffer = Vector{Int}(undef, batch_size)
    return (ch, buffer)
end

for batch_size in BATCH_SIZES
    SUITE["batch"]["take!_buffer_batch=$batch_size"] = @benchmarkable(
        take!(ch, buffer),
        setup = ((ch, buffer) = setup_batch_take_buffer($batch_size)),
        teardown = (close(ch))
    )
end
