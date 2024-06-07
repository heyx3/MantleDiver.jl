
"""
Each grid cell can be occupied by a different entity.
However, for ubiquitous things like rocks, this is very inefficient.
So you can also write a "bulk" grid entity which manages an unlimited set of simple objects.

Only one bulk component can exist for each type of grid object.
"""
@component BulkElements{T} {abstract} {worldSingleton} {require: DrillResponse} begin
    lookup::Dict{v3i, T}

    # Callbacks should have the signature (v3i, T) -> Nothing
    on_element_added::Set{Base.Callable}
    on_element_removed::Set{Base.Callable}

    function CONSTRUCT()
        this.lookup = Dict{v3i, T}()
        this.on_element_added = Set{Base.Callable}()
        this.on_element_removed = Set{Base.Callable}()
    end

    "Implements the core logic for the user-facing `bulk_is_passable()`"
    @promise is_passable(grid_idx::v3i, data::T)::Bool
end

function bulk_create_at( b::BulkElements{T},
                         grid_idx::v3i,
                         new_data::T,
                         ::Type{T} = typeof(new_data)
                       )::Nothing where {T}
    @d8_assert(!haskey(b.lookup, grid_idx),
               "Trying to create bulk ", T, " at location which already has one: ", grid_idx)
    b.lookup[grid_idx] = new_data
    for callback in b.on_element_added
        callback(grid_idx, new_data)
    end
    return nothing
end
function bulk_destroy_at(b::BulkElements{T}, grid_idx::v3i)::T where {T}
    @d8_assert(haskey(b.lookup, grid_idx),
               "Trying to destroy nonexistent bulk ", T, " at ", grid_idx)
    deleted = b.lookup[grid_idx]
    delete!(b.lookup, grid_idx)
    for callback in b.on_element_removed
        callback(grid_idx, deleted)
    end
    return deleted
end
function bulk_data_at(b::BulkElements{T}, grid_idx::v3i)::Optional{T} where {T}
    return get(b.lookup, grid_idx, nothing)
end
function bulk_is_passable(b::BulkElements{T}, grid_idx::v3i)::Bool where {T}
    return b.is_passable(grid_idx, bulk_data_at(b, grid_idx))
end
"
Notifies a bulk component that all its entities in the given chunk are being destroyed.
By default, calls `bulk_destroy_at()` for each element in the chunk.
"
function bulk_destroy_chunk(b::BulkElements, chunk_idx::v3i, is_world_grid_dying::Bool)
    for world_grid_idx::v3i in grid_idcs_in_chunk(chunk_idx)
        if haskey(b.lookup, world_grid_idx)
            bulk_destroy_at(b, world_grid_idx)
        end
    end
end


"An element within a bulk entity, represented with its world-grid index"
const BulkEntity{B<:BulkElements} = Tuple{B, v3i}
