using Documenter
using PipeChannels

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
