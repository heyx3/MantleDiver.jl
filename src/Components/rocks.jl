# Minerals are named after the thing they're spent on.
@bp_enum(Minerals,
    Storage,
    Hull,
    Drill,
    Specials,
    Sensors,
    Maneuvers
)

"Some data, per-mineral, stored in a `Vec`"
const PerMineral{T} = Vec{length(Minerals.instances()), T}

@component Rock {entitySingleton} {require: GridElement} begin
    minerals::PerMineral{Float32}
end