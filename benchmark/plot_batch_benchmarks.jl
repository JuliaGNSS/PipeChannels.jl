using BenchmarkTools
using PipeChannels
using CairoMakie

# Include benchmark definitions
include("benchmarks.jl")

if Threads.nthreads() < 2
    @warn "Running with $(Threads.nthreads()) thread(s). For best results showing multi-core performance, run with: julia -t 2 --project=. plot_batch_benchmarks.jl"
end

println("Running batch benchmarks with $(Threads.nthreads()) thread(s)... (this may take a few minutes)")

# Run only the batch benchmark suite
results = run(SUITE["batch"], verbose=true, seconds=5)

# Extract results for plotting
batch_sizes = [8, 16, 32, 64, 128, 256]

# Throughput benchmarks (time in ms) - using minimum
single_time = minimum(results["single"]).time / 1e6  # ns to ms
batch_times = Float64[]
batch_speedups = Float64[]

for batch_size in batch_sizes
    batch_time = minimum(results["batch=$batch_size"]).time / 1e6
    push!(batch_times, batch_time)
    push!(batch_speedups, single_time / batch_time)
end

# Individual operation benchmarks - time per item (ns)
single_put_time = minimum(SUITE["pipechannel"]["put!"] |> run).time
single_take_time = minimum(SUITE["pipechannel"]["take!"] |> run).time

batch_put_times = Float64[]
batch_take_times = Float64[]
batch_take_buffer_times = Float64[]

for batch_size in batch_sizes
    # Time per item = total time / batch size
    put_time = minimum(results["put!_batch=$batch_size"]).time / batch_size
    take_time = minimum(results["take!_batch=$batch_size"]).time / batch_size
    take_buffer_time = minimum(results["take!_buffer_batch=$batch_size"]).time / batch_size
    push!(batch_put_times, put_time)
    push!(batch_take_times, take_time)
    push!(batch_take_buffer_times, take_buffer_time)
end

# Create the plot
fig = Figure(size=(1200, 800))

# Plot 1: Throughput speedup vs batch size
ax1 = Axis(fig[1, 1],
    xlabel="Batch Size",
    ylabel="Speedup vs Single Operations",
    title="Throughput Speedup (10,000 items)",
    xticks=(1:length(batch_sizes), string.(batch_sizes))
)

barplot!(ax1, 1:length(batch_sizes), batch_speedups, color=:coral)

# Add speedup annotations
for (i, speedup) in enumerate(batch_speedups)
    text!(ax1, i, speedup + 0.5, text="$(round(speedup, digits=1))x",
          align=(:center, :bottom), fontsize=10)
end

# Add reference line at 1x
hlines!(ax1, [1.0], color=:gray, linestyle=:dash, label="Single ops baseline")

# Plot 2: Absolute throughput times
all_times = [single_time; batch_times]
ax2 = Axis(fig[1, 2],
    xlabel="Batch Size",
    ylabel="Time (ms)",
    title="Throughput Time (10,000 items)",
    xticks=(1:length(all_times), ["Single"; string.(batch_sizes)])
)

colors = [:steelblue; fill(:coral, length(batch_sizes))]
barplot!(ax2, 1:length(all_times), all_times, color=colors)

# Plot 3: put! time per item comparison
ax3 = Axis(fig[2, 1],
    xlabel="Batch Size",
    ylabel="Time per item (ns)",
    title="put! Time per Item",
    xticks=(1:length(batch_sizes)+1, ["Single"; string.(batch_sizes)])
)

all_put_times = [single_put_time; batch_put_times]
colors_put = [:steelblue; fill(:coral, length(batch_sizes))]
barplot!(ax3, 1:length(all_put_times), all_put_times, color=colors_put)

# Add speedup annotations for put!
for (i, t) in enumerate(batch_put_times)
    speedup = single_put_time / t
    text!(ax3, i + 1, t + single_put_time * 0.03,
          text="$(round(speedup, digits=1))x",
          align=(:center, :bottom), fontsize=9)
end

# Plot 4: take! time per item comparison
ax4 = Axis(fig[2, 2],
    xlabel="Batch Size",
    ylabel="Time per item (ns)",
    title="take! Time per Item (allocating vs buffer)",
    xticks=(1:length(batch_sizes)+1, ["Single"; string.(batch_sizes)])
)

# Group bars for allocating vs buffer take!
barwidth = 0.35
x = 2:length(batch_sizes)+1

# Single operation
barplot!(ax4, [1], [single_take_time], width=0.6, color=:steelblue)

# Batch allocating
barplot!(ax4, x .- barwidth/2, batch_take_times, width=barwidth,
         color=:coral, label="take!(ch, n)")

# Batch with buffer
barplot!(ax4, x .+ barwidth/2, batch_take_buffer_times, width=barwidth,
         color=:mediumpurple, label="take!(ch, buffer)")

axislegend(ax4, position=:rt)

# Add overall title
Label(fig[0, :], "Batch Operations Performance", fontsize=20, font=:bold)

# Save the figure
save("batch_benchmark_comparison.png", fig, px_per_unit=2)
println("\nPlot saved to benchmark/batch_benchmark_comparison.png")

# Print summary
println("\n" * "="^60)
println("BATCH BENCHMARK SUMMARY")
println("="^60)

println("\nThroughput (10,000 items):")
println("-"^50)
println("  Single operations: $(round(single_time, digits=2))ms")
for (i, batch_size) in enumerate(batch_sizes)
    println("  Batch size $batch_size: $(round(batch_times[i], digits=2))ms ($(round(batch_speedups[i], digits=1))x faster)")
end

println("\nPer-item operation times:")
println("-"^50)
println("  Single put!: $(round(single_put_time, digits=1))ns")
println("  Single take!: $(round(single_take_time, digits=1))ns")
println()
for (i, batch_size) in enumerate(batch_sizes)
    put_speedup = single_put_time / batch_put_times[i]
    take_speedup = single_take_time / batch_take_times[i]
    take_buffer_speedup = single_take_time / batch_take_buffer_times[i]
    println("  Batch $batch_size:")
    println("    put!: $(round(batch_put_times[i], digits=1))ns/item ($(round(put_speedup, digits=1))x faster)")
    println("    take!(n): $(round(batch_take_times[i], digits=1))ns/item ($(round(take_speedup, digits=1))x faster)")
    println("    take!(buffer): $(round(batch_take_buffer_times[i], digits=1))ns/item ($(round(take_buffer_speedup, digits=1))x faster)")
end
