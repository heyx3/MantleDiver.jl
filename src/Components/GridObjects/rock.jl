# Minerals are named after the thing they're spent on.
@bp_enum(Mineral,
    storage,
    hull,
    drill,
    specials,
    sensors,
    maneuvers
)

"Some per-mineral data, stored in an immutable array"
const PerMineral{T} = Vec{length(Mineral.instances()), T}
@inline getindex(pm::PerMineral, m::E_Mineral) = pm[Int32(m)]

@component Rock {entitySingleton} {require: GridElement} begin
    minerals::PerMineral{Float32}

    function CONSTRUCT(minerals::PerMineral{Float32})
        this.minerals = minerals
        get_component(entity, GridElement).is_solid = true
    end
end