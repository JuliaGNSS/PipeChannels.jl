using Documenter
using PipeChannels

# Copy benchmark images to docs assets folder
assets_dir = joinpath(@__DIR__, "src", "assets")
mkpath(assets_dir)
cp(
    joinpath(@__DIR__, "..", "benchmark", "benchmark_comparison.png"),
    joinpath(assets_dir, "benchmark_comparison.png"),
    force=true
)
cp(
    joinpath(@__DIR__, "..", "benchmark", "batch_benchmark_comparison.png"),
    joinpath(assets_dir, "batch_benchmark_comparison.png"),
    force=true
)

makedocs(
    sitename = "PipeChannels.jl",
    modules = [PipeChannels],
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true"
    ),
    pages = [
        "Home" => "index.md",
        "API Reference" => "api.md",
    ],
)

deploydocs(
    repo = "github.com/JuliaGNSS/PipeChannels.jl.git",
    devbranch = "main",
)
