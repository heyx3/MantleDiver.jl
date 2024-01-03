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

"Per-rock data, stored by the `RockBulkGridElement`"
struct Rock
    minerals::PerMineral{Float32}
end

@component RockBulkGridElement<:AbstractBulkGridElement {entitySingleton} begin
    lookup::Dict{v3i, Rock}

    function CONSTRUCT()
        SUPER()
        this.lookup = Dict{v3i, Rock}()
    end

    function create_at(i::v3i, rock::Rock)
        @d8_assert(!haskey(this.lookup, i),
                   "Trying to create rock at location which already has rock: ", i)
        this.lookup[i] = rock
        return nothing
    end
    function destroy_at(i::v3i)::Rock
        @d8_assert(haskey(this.lookup, i),
                   "Trying to destroy nonexistent rock: ", i)
        deleted = this.lookup[i]
        delete!(this.lookup, i)
        return deleted
    end

    function data_at(i::v3i)::Optional{Rock}
        return get(this.lookup, i, nothing)
    end

    is_passable(i::v3i) = false
end