# PipeChannels.jl

A lock-free single-producer single-consumer (SPSC) channel for Julia.

## Why PipeChannels?

Julia's built-in `Channel` type is excellent for general-purpose concurrent programming, but it allocates memory on every `put!` and `take!` operation due to its task scheduling and condition variable infrastructure. This is usually fine, but in **real-time applications** where consistent latency matters (such as SDR signal processing, audio processing, or high-frequency trading), these allocations can trigger garbage collection pauses at unpredictable times.

`PipeChannel` solves this by using a lock-free ring buffer with atomic operations. The trade-off is that it only supports **exactly one producer thread and one consumer thread** - but for many streaming pipelines, this is exactly the pattern you need.

### Performance

![Benchmark comparison](assets/benchmark_comparison.png)

## Installation

```julia
using Pkg
Pkg.add("PipeChannels")
```

## Quick Start

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

## Thread Safety

!!! warning "Single Producer, Single Consumer"
    `PipeChannel` is designed for exactly **one producer thread** and **one consumer thread**.
    Using multiple producers or multiple consumers will cause data races and undefined behavior.

This constraint enables the lock-free implementation that provides zero-allocation performance.

## Contents

```@contents
Pages = ["api.md"]
```
