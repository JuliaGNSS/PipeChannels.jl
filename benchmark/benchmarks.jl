using BenchmarkTools
using PipeChannels

const SUITE = BenchmarkGroup()

# Include individual benchmark files
include("pipechannel_benchmarks.jl")
include("channel_benchmarks.jl")
include("batch_benchmarks.jl")
