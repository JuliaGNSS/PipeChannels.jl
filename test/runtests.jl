using Test
using PipeChannels

@testset "PipeChannels.jl" begin

    @testset "Basic Operations" begin
        ch = PipeChannel{Int}(16)

        @test isopen(ch)
        @test isempty(ch)
        @test !isready(ch)
        @test !isfull(ch)
        @test Base.n_avail(ch) == 0
        @test eltype(ch) == Int

        put!(ch, 42)
        @test !isempty(ch)
        @test isready(ch)
        @test Base.n_avail(ch) == 1

        val = take!(ch)
        @test val == 42
        @test isempty(ch)
        @test Base.n_avail(ch) == 0

        close(ch)
        @test !isopen(ch)
    end

    @testset "Multiple Values" begin
        ch = PipeChannel{Int}(16)

        for i in 1:10
            put!(ch, i)
        end
        @test Base.n_avail(ch) == 10

        for i in 1:10
            @test take!(ch) == i
        end
        @test isempty(ch)

        close(ch)
    end

    @testset "Fill to Capacity" begin
        capacity = 8
        ch = PipeChannel{Int}(capacity)

        # Fill the buffer
        for i in 1:capacity
            put!(ch, i)
        end
        @test isfull(ch)
        @test Base.n_avail(ch) == capacity

        # Drain it
        for i in 1:capacity
            @test take!(ch) == i
        end
        @test isempty(ch)
        @test !isfull(ch)

        close(ch)
    end

    @testset "Iteration" begin
        ch = PipeChannel{Int}(16)

        for i in 1:5
            put!(ch, i)
        end
        close(ch)

        collected = collect(ch)
        @test collected == [1, 2, 3, 4, 5]
    end

    @testset "Closed Channel Throws" begin
        ch = PipeChannel{Int}(16)
        close(ch)

        @test_throws InvalidStateException put!(ch, 1)
        @test_throws InvalidStateException take!(ch)
    end

    @testset "Take from Closed with Data" begin
        ch = PipeChannel{Int}(16)
        put!(ch, 1)
        put!(ch, 2)
        close(ch)

        # Should still be able to take existing data
        @test take!(ch) == 1
        @test take!(ch) == 2

        # Now should throw
        @test_throws InvalidStateException take!(ch)
    end

    @testset "eltype" begin
        @test eltype(PipeChannel{Int}) == Int
        @test eltype(PipeChannel{String}) == String
        @test eltype(PipeChannel{ComplexF64}) == ComplexF64

        ch = PipeChannel{Float32}(8)
        @test eltype(ch) == Float32
        close(ch)
    end

    @testset "Capacity Validation" begin
        @test_throws ArgumentError PipeChannel{Int}(0)
        @test_throws ArgumentError PipeChannel{Int}(-1)

        # Capacity 1 should work
        ch = PipeChannel{Int}(1)
        put!(ch, 42)
        @test take!(ch) == 42
        close(ch)
    end

    @testset "wait Function" begin
        ch = PipeChannel{Int}(16)

        # Start a task that will put data after a short delay
        task = @async begin
            sleep(0.01)
            put!(ch, 42)
        end

        # wait should return once data is available
        wait(ch)
        @test isready(ch)
        @test take!(ch) == 42

        wait(task)
        close(ch)
    end

    @testset "wait on Closed Empty Channel Throws" begin
        ch = PipeChannel{Int}(16)
        close(ch)

        @test_throws InvalidStateException wait(ch)
    end

    @testset "bind Task Success" begin
        ch = PipeChannel{Int}(16)

        task = @async begin
            for i in 1:5
                put!(ch, i)
            end
            close(ch)
        end
        bind(ch, task)

        collected = collect(ch)
        @test collected == [1, 2, 3, 4, 5]
        @test !isopen(ch)
    end

    @testset "bind Task Failure" begin
        ch = PipeChannel{Int}(16)

        task = @async begin
            put!(ch, 1)
            error("Task failed!")
        end
        bind(ch, task)

        # First value should be available
        @test take!(ch) == 1

        # Give the async task time to fail and close the channel
        sleep(0.1)

        # Subsequent operations should throw TaskFailedException
        @test_throws TaskFailedException take!(ch)
    end

    @testset "Threaded Producer-Consumer" begin
        if Threads.nthreads() >= 2
            ch = PipeChannel{Int}(64)
            n_items = 1000

            producer = Threads.@spawn begin
                for i in 1:n_items
                    put!(ch, i)
                end
                close(ch)
            end

            results = Int[]
            consumer = Threads.@spawn begin
                for val in ch
                    push!(results, val)
                end
            end

            wait(producer)
            wait(consumer)

            @test length(results) == n_items
            @test results == collect(1:n_items)
        else
            @info "Skipping threaded test (need at least 2 threads)"
        end
    end

    @testset "Batch put!" begin
        ch = PipeChannel{Int}(16)

        # Write a batch
        data = [1, 2, 3, 4, 5]
        result = put!(ch, data)
        @test result === data  # Returns the input vector
        @test Base.n_avail(ch) == 5

        # Read back and verify
        for i in 1:5
            @test take!(ch) == i
        end

        close(ch)
    end

    @testset "Batch put! blocking" begin
        # Test that batch put! blocks when buffer is full
        ch = PipeChannel{Int}(4)

        # This should block until consumer drains some items
        producer = @async put!(ch, collect(1:10))

        # Give producer time to start
        sleep(0.01)

        # Drain items - this should unblock the producer
        results = Int[]
        for _ in 1:10
            push!(results, take!(ch))
        end

        wait(producer)
        @test results == collect(1:10)

        close(ch)
    end

    @testset "Batch take! with count" begin
        ch = PipeChannel{Int}(16)

        # Fill channel
        for i in 1:10
            put!(ch, i)
        end

        # Take a batch
        result = take!(ch, 5)
        @test result == [1, 2, 3, 4, 5]
        @test Base.n_avail(ch) == 5

        # Take remaining
        result = take!(ch, 5)
        @test result == [6, 7, 8, 9, 10]

        close(ch)
    end

    @testset "Batch take! blocking" begin
        # Test that batch take! blocks when not enough data
        ch = PipeChannel{Int}(16)

        # Start consumer that wants 10 items
        consumer = @async take!(ch, 10)

        # Give consumer time to start
        sleep(0.01)

        # Producer sends items - this should unblock the consumer
        for i in 1:10
            put!(ch, i)
        end

        result = fetch(consumer)
        @test result == collect(1:10)

        close(ch)
    end

    @testset "Batch take! with output buffer" begin
        ch = PipeChannel{Int}(16)

        # Fill channel
        for i in 1:10
            put!(ch, i)
        end

        # Take into pre-allocated buffer
        buffer = Vector{Int}(undef, 5)
        n = take!(ch, buffer)
        @test n == 5
        @test buffer == [1, 2, 3, 4, 5]

        # Take remaining
        buffer = Vector{Int}(undef, 5)
        n = take!(ch, buffer)
        @test n == 5
        @test buffer == [6, 7, 8, 9, 10]

        close(ch)
    end

    @testset "Batch operations wraparound" begin
        # Test that batch operations work correctly when buffer wraps around
        ch = PipeChannel{Int}(8)

        # Fill partially, then drain
        for i in 1:5
            put!(ch, i)
        end
        for _ in 1:5
            take!(ch)
        end

        # Now head and tail are at position 6
        # Write a batch that will wrap around
        data = collect(1:6)
        put!(ch, data)
        @test Base.n_avail(ch) == 6

        # Take as batch
        result = take!(ch, 6)
        @test result == [1, 2, 3, 4, 5, 6]

        close(ch)
    end

    @testset "Batch on closed channel" begin
        ch = PipeChannel{Int}(16)
        close(ch)

        # put! on closed channel should throw
        @test_throws InvalidStateException put!(ch, [1, 2, 3])

        # take! on closed empty channel should throw
        @test_throws InvalidStateException take!(ch, 5)
        buffer = Vector{Int}(undef, 5)
        @test_throws InvalidStateException take!(ch, buffer)
    end

end
