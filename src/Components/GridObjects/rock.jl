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

"Per-rock data, stored in a bulk grid entity"
struct Rock
    minerals::PerMineral{Float32}
end

const RockBulkElements = BulkElements{Rock}
bulk_data_is_passable(::RockBulkElements, ::v3i, ::Rock) = false


"A rock's response to being drilled"
@component RockDrillResponse <: DrillResponse {require: RockBulkElements} begin
    # Default behavior is fine
end