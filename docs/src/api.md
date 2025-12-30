# API Reference

## PipeChannel Type

```@docs
PipeChannel
```

## Channel Operations

```@docs
Base.put!(::PipeChannel{T}, ::T) where T
Base.take!(::PipeChannel)
Base.close(::PipeChannel)
Base.bind(::PipeChannel, ::Task)
```

## Query Functions

```@docs
Base.isopen(::PipeChannel)
Base.isready(::PipeChannel)
Base.isempty(::PipeChannel)
Base.isfull(::PipeChannel)
Base.n_avail(::PipeChannel)
Base.wait(::PipeChannel)
```

## Iteration

`PipeChannel` supports Julia's iteration protocol. You can iterate over values until the channel is closed and empty:

```julia
ch = PipeChannel{Int}(16)
for i in 1:5
    put!(ch, i)
end
close(ch)

for value in ch
    println(value)
end
# Output: 1, 2, 3, 4, 5
```

```@docs
Base.iterate(::PipeChannel{T}, ::Any) where T
Base.eltype(::Type{PipeChannel{T}}) where T
Base.IteratorSize(::Type{<:PipeChannel})
```
