# PipeChannels.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaGNSS.github.io/PipeChannels.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaGNSS.github.io/PipeChannels.jl/dev/)
[![Build Status](https://github.com/JuliaGNSS/PipeChannels.jl/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/JuliaGNSS/PipeChannels.jl/actions/workflows/ci.yml?query=branch%3Amain)

A lock-free single-producer single-consumer (SPSC) channel for Julia.

## Why PipeChannels?

Julia's built-in `Channel` type is excellent for general-purpose concurrent programming, but it allocates memory on every `put!` and `take!` operation due to its task scheduling and condition variable infrastructure. This is usually fine, but in **real-time applications** where consistent latency matters (such as SDR signal processing, audio processing, or high-frequency trading), these allocations can trigger garbage collection pauses at unpredictable times.

`PipeChannel` solves this by using a lock-free ring buffer with atomic operations. The trade-off is that it only supports **exactly one producer thread and one consumer thread** - but for many streaming pipelines, this is exactly the pattern you need.

### Performance

![Benchmark comparison](benchmark/benchmark_comparison.png)

## Installation

```julia
using Pkg
Pkg.add("PipeChannels")
```

## Usage

The API matches Julia's `Channel`:

```julia
using PipeChannels

# Create a channel with capacity 16
ch = PipeChannel{Int}(16)

# Producer thread
producer = Threads.@spawn begin
    for i in 1:100
        put!(ch, i)
    end
    close(ch)
end

# Consumer thread
consumer = Threads.@spawn begin
    for value in ch
        println("Received: ", value)
    end
end

wait(producer)
wait(consumer)
```

### Error Propagation with `bind`

Just like `Channel`, you can bind a task to automatically close the channel and propagate errors:

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

## API Reference

### Constructor
- `PipeChannel{T}(capacity::Integer)` - Create a channel with the given buffer capacity

### Channel Operations
- `put!(ch, value)` - Add an element (blocks if full)
- `take!(ch)` - Remove and return an element (blocks if empty)
- `close(ch)` - Close the channel
- `bind(ch, task)` - Bind a task for automatic close and error propagation

### Query Functions
- `isopen(ch)` - Check if channel is open
- `isready(ch)` - Check if data is available
- `isempty(ch)` - Check if buffer is empty
- `isfull(ch)` - Check if buffer is full
- `n_avail(ch)` - Number of elements available to read
- `eltype(ch)` - Element type of the channel

### Iteration
- `for x in ch` - Iterate until channel is closed and empty

## Thread Safety

**Important constraints:**
- Exactly **ONE** producer thread may call `put!`
- Exactly **ONE** consumer thread may call `take!`
- Multiple producers or consumers will cause data races

This is not a limitation for most streaming pipelines where you have a single data source feeding a single processor.

## License

MIT License - see [LICENSE](LICENSE) for details.
