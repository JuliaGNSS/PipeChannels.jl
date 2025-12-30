using BenchmarkTools
using PipeChannels

# Number of items to push through the channel per benchmark iteration
const PIPECHANNEL_NUM_ITEMS = 10_000

# Setup: create PipeChannel ready to run
function setup_pipechannel_benchmark(buffer_size::Int)
    ch = PipeChannel{Int}(buffer_size)
    return ch
end

# Benchmark: push data through the channel and drain output
function run_pipechannel_benchmark!(ch::PipeChannel{Int}, num_items::Int)
    # Producer task
    producer = Threads.@spawn begin
        for i in 1:num_items
            put!(ch, i)
        end
        close(ch)
    end

    # Consumer task
    consumer = Threads.@spawn begin
        for _ in ch
            # discard
        end
    end

    wait(producer)
    wait(consumer)
    return nothing
end

# Buffer sizes to test
const PIPECHANNEL_BUFFER_SIZES = [1, 4, 16, 64, 256, 1024]

SUITE["pipechannel"] = BenchmarkGroup()

for buf_size in PIPECHANNEL_BUFFER_SIZES
    SUITE["pipechannel"]["buffer=$buf_size"] = @benchmarkable(
        run_pipechannel_benchmark!(ch, PIPECHANNEL_NUM_ITEMS),
        setup = (ch = setup_pipechannel_benchmark($buf_size)),
        evals = 1
    )
end

# Benchmarks for individual put! and take! operations
# Uses a large buffer so put!/take! don't block

# put! benchmark: start with empty buffer, put many times
function setup_pipechannel_put()
    ch = PipeChannel{Int}(1024)
    return ch
end

SUITE["pipechannel"]["put!"] = @benchmarkable(
    put!(ch, 1),
    setup = (ch = setup_pipechannel_put()),
    teardown = (close(ch))
)

# take! benchmark: start with full buffer, take many times
function setup_pipechannel_take()
    ch = PipeChannel{Int}(1024)
    for i in 1:1024
        put!(ch, i)
    end
    return ch
end

SUITE["pipechannel"]["take!"] = @benchmarkable(
    take!(ch),
    setup = (ch = setup_pipechannel_take()),
    teardown = (close(ch))
)
