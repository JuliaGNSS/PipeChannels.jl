using BenchmarkTools
using PipeChannels
using CairoMakie

# Include benchmark definitions
include("benchmarks.jl")

if Threads.nthreads() < 2
    @warn "Running with $(Threads.nthreads()) thread(s). For best results showing multi-core performance, run with: julia -t 2 --project=. plot_benchmarks.jl"
end

println("Running benchmarks with $(Threads.nthreads()) thread(s)... (this may take a few minutes)")

# Run the benchmark suite
results = run(SUITE, verbose=true, seconds=5)

# Extract results for plotting
buffer_sizes = [1, 4, 16, 64, 256, 1024]

# Throughput benchmarks (time in ms) - using minimum
pipechannel_times = Float64[]
channel_times = Float64[]
pipechannel_allocs = Float64[]
channel_allocs = Float64[]

for buf_size in buffer_sizes
    pc_result = results["pipechannel"]["buffer=$buf_size"]
    ch_result = results["channel"]["buffer=$buf_size"]
    push!(pipechannel_times, minimum(pc_result).time / 1e6)  # ns to ms
    push!(channel_times, minimum(ch_result).time / 1e6)
    push!(pipechannel_allocs, minimum(pc_result).memory / 1024)  # bytes to KB
    push!(channel_allocs, minimum(ch_result).memory / 1024)
end

# Individual operation benchmarks (time in ns) - using minimum
pc_put_time = minimum(results["pipechannel"]["put!"]).time
ch_put_time = minimum(results["channel"]["put!"]).time
pc_take_time = minimum(results["pipechannel"]["take!"]).time
ch_take_time = minimum(results["channel"]["take!"]).time

pc_put_alloc = minimum(results["pipechannel"]["put!"]).memory
ch_put_alloc = minimum(results["channel"]["put!"]).memory
pc_take_alloc = minimum(results["pipechannel"]["take!"]).memory
ch_take_alloc = minimum(results["channel"]["take!"]).memory

# Create the plot
fig = Figure(size=(1200, 1000))

barwidth = 0.35
x = 1:length(buffer_sizes)

# Plot 1: Throughput comparison (time) - linear scale
ax1 = Axis(fig[1, 1],
    xlabel="Buffer Size",
    ylabel="Time (ms)",
    title="Throughput: 10,000 items (Time)",
    xticks=(1:length(buffer_sizes), string.(buffer_sizes))
)

barplot!(ax1, x .- barwidth/2, channel_times, width=barwidth, label="Channel", color=:steelblue)
barplot!(ax1, x .+ barwidth/2, pipechannel_times, width=barwidth, label="PipeChannel", color=:coral)
axislegend(ax1, position=:rt)

# Add speedup annotations for time
for (i, (ch_t, pc_t)) in enumerate(zip(channel_times, pipechannel_times))
    speedup = ch_t / pc_t
    text!(ax1, i, max(ch_t, pc_t) * 1.05, text="$(round(speedup, digits=1))x",
          align=(:center, :bottom), fontsize=10)
end

# Plot 2: Throughput comparison (allocations) - linear scale
ax2 = Axis(fig[1, 2],
    xlabel="Buffer Size",
    ylabel="Allocations (KB)",
    title="Throughput: 10,000 items (Allocations)",
    xticks=(1:length(buffer_sizes), string.(buffer_sizes))
)

barplot!(ax2, x .- barwidth/2, channel_allocs, width=barwidth, label="Channel", color=:steelblue)
barplot!(ax2, x .+ barwidth/2, pipechannel_allocs, width=barwidth, label="PipeChannel", color=:coral)
axislegend(ax2, position=:lt)

# Add reduction annotations for allocations
for (i, (ch_a, pc_a)) in enumerate(zip(channel_allocs, pipechannel_allocs))
    if pc_a > 0
        reduction = ch_a / pc_a
        text!(ax2, i, max(ch_a, pc_a) * 1.05, text="$(round(reduction, digits=1))x",
              align=(:center, :bottom), fontsize=10)
    else
        text!(ax2, i, ch_a * 1.05, text="∞",
              align=(:center, :bottom), fontsize=10)
    end
end

# Plot 3: put! time comparison
ax3 = Axis(fig[2, 1],
    xlabel="Channel Type",
    ylabel="Time (ns)",
    title="Single put! operation (Time)",
    xticks=(1:2, ["Channel", "PipeChannel"])
)

barplot!(ax3, [1, 2], [ch_put_time, pc_put_time], color=[:steelblue, :coral])

put_speedup = ch_put_time / pc_put_time
text!(ax3, 1.7, max(ch_put_time, pc_put_time) * 0.85,
      text="$(round(put_speedup, digits=1))x faster", align=(:center, :bottom), fontsize=12)

# Plot 4: take! time comparison
ax4 = Axis(fig[2, 2],
    xlabel="Channel Type",
    ylabel="Time (ns)",
    title="Single take! operation (Time)",
    xticks=(1:2, ["Channel", "PipeChannel"])
)

barplot!(ax4, [1, 2], [ch_take_time, pc_take_time], color=[:steelblue, :coral])

take_speedup = ch_take_time / pc_take_time
text!(ax4, 1.7, max(ch_take_time, pc_take_time) * 0.85,
      text="$(round(take_speedup, digits=1))x faster", align=(:center, :bottom), fontsize=12)

# Plot 5: put! allocations comparison
ax5 = Axis(fig[3, 1],
    xlabel="Channel Type",
    ylabel="Allocations (bytes)",
    title="Single put! operation (Allocations)",
    xticks=(1:2, ["Channel", "PipeChannel"])
)

barplot!(ax5, [1, 2], [ch_put_alloc, pc_put_alloc], color=[:steelblue, :coral])

if pc_put_alloc > 0
    put_alloc_reduction = ch_put_alloc / pc_put_alloc
    text!(ax5, 1.7, max(ch_put_alloc, pc_put_alloc) * 0.85,
          text="$(round(put_alloc_reduction, digits=1))x less", align=(:center, :bottom), fontsize=12)
elseif ch_put_alloc > 0
    text!(ax5, 1.7, ch_put_alloc * 0.85,
          text="zero allocs!", align=(:center, :bottom), fontsize=12)
end

# Plot 6: take! allocations comparison
ax6 = Axis(fig[3, 2],
    xlabel="Channel Type",
    ylabel="Allocations (bytes)",
    title="Single take! operation (Allocations)",
    xticks=(1:2, ["Channel", "PipeChannel"])
)

barplot!(ax6, [1, 2], [ch_take_alloc, pc_take_alloc], color=[:steelblue, :coral])

if pc_take_alloc > 0
    take_alloc_reduction = ch_take_alloc / pc_take_alloc
    text!(ax6, 1.5, max(ch_take_alloc, pc_take_alloc) * 1.1,
          text="$(round(take_alloc_reduction, digits=1))x less", align=(:center, :bottom), fontsize=12)
elseif ch_take_alloc > 0
    text!(ax6, 1.5, ch_take_alloc * 1.1,
          text="zero allocs!", align=(:center, :bottom), fontsize=12)
end

# Add overall title
Label(fig[0, :], "PipeChannel vs Channel Performance Comparison", fontsize=20, font=:bold)

# Save the figure
save("benchmark_comparison.png", fig, px_per_unit=2)
println("\nPlot saved to benchmark/benchmark_comparison.png")

# Print summary
println("\n" * "="^60)
println("BENCHMARK SUMMARY (using minimum)")
println("="^60)
println("\nThroughput (10,000 items):")
println("-"^50)
for (i, buf_size) in enumerate(buffer_sizes)
    speedup = channel_times[i] / pipechannel_times[i]
    alloc_ratio = pipechannel_allocs[i] > 0 ? channel_allocs[i] / pipechannel_allocs[i] : Inf
    println("  Buffer=$buf_size:")
    println("    Time:   Channel=$(round(channel_times[i], digits=2))ms, " *
            "PipeChannel=$(round(pipechannel_times[i], digits=2))ms ($(round(speedup, digits=1))x faster)")
    println("    Allocs: Channel=$(round(channel_allocs[i], digits=1))KB, " *
            "PipeChannel=$(round(pipechannel_allocs[i], digits=1))KB ($(round(alloc_ratio, digits=1))x less)")
end

println("\nIndividual operations:")
println("-"^50)
println("  put!:")
println("    Time:   Channel=$(round(ch_put_time, digits=1))ns, " *
        "PipeChannel=$(round(pc_put_time, digits=1))ns ($(round(put_speedup, digits=1))x faster)")
println("    Allocs: Channel=$(ch_put_alloc)B, PipeChannel=$(pc_put_alloc)B")
println("  take!:")
println("    Time:   Channel=$(round(ch_take_time, digits=1))ns, " *
        "PipeChannel=$(round(pc_take_time, digits=1))ns ($(round(take_speedup, digits=1))x faster)")
println("    Allocs: Channel=$(ch_take_alloc)B, PipeChannel=$(pc_take_alloc)B")
