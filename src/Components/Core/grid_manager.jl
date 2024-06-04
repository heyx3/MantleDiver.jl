# Certain things in the game world (mostly rocks) are organized into a uniform grid.
# This grid is managed in chunks; new chunks are generated as the player goes deeper.
# Chunks' initial elements are filled in by a GridGenerator.
# The chunks, manager, and generator all live on a single entity.


##  GridGenerator  ##

@component GridGenerator {abstract} {worldSingleton} begin
    @promise generate(world_grid_idx::v3i)::Optional{Union{Entity, BulkElements}}
end


##   Chunk   ##

const CHUNK_SIZE = v3i(8, 8, 8)

"Gets the chunk covering a given grid postion"
function chunk_idx(world_grid_pos::Vec3)::v3i
    i = grid_idx(world_grid_pos) # If continuous, turn into voxel
    return vselect(
        i ÷ CHUNK_SIZE,
        (i - CHUNK_SIZE + Int32(1)) ÷ CHUNK_SIZE,
        i < 0
    )
end
"Gets the min grid position within the given chunk"
function chunk_first_grid_idx(chunk_idx::v3i)
    return chunk_idx * CHUNK_SIZE
end
"Gets the array index for the given grid position within the given chunk"
function chunk_grid_idx(chunk_idx::v3i, world_grid_pos::Vec3)::typeof(world_grid_pos)
    first_grid_pos = chunk_first_grid_idx(chunk_idx)
    ONE = one(eltype(world_grid_pos))
    return world_grid_pos - first_grid_pos + ONE
end


@component GridChunk {require: GridGenerator} begin
    idx::v3i # Multiply by the chunk size to get the first grid index in this chunk
    elements::Array{Optional{Union{Entity, BulkElements}}, 3}

    function CONSTRUCT(idx::v3i)
        this.idx = idx
        first_world_idx::v3i = this.idx * CHUNK_SIZE

        # Fill in the chunk array using this world's generator.
        # Dispatch to a function where the generator type is known at compile-time.
        function generate_chunk(gen::T) where {T<:GridGenerator}
            Optional{Union{Entity, BulkElements}}[
                gen.generate(first_world_idx + v3i(x, y, z) - Int32(1))
                  for x in 1:CHUNK_SIZE.x,
                      y in 1:CHUNK_SIZE.y,
                      z in 1:CHUNK_SIZE.z
            ]
        end
        this.elements = generate_chunk(get_component(entity, GridGenerator))
    end
    function DESTRUCT(is_world_grid_dying::Bool)
        # Kill all grid entities within this chunk.
        for idx in 1:vsize(this.elements)
            element = this.elements[idx]
            if exists(element)
                if element isa BulkElements
                    world_idx = (idx - Int32(1)) + (this.idx * CHUNK_SIZE)
                    bulk_destroy_at(element, world_idx)
                else
                    remove_entity(world, element)
                end
            end
        end
        # Un-register this chunk with the manager component.
        if !is_world_grid_dying
            grid = get_component(entity, GridManager)
            delete!(grid.chunks, this.idx)
        end
    end
end


##   Manager of chunks   ##

@component GridManager {worldSingleton} begin
    chunks::Dict{v3i, GridChunk}
    bulk_entities::Dict{Type, Any} # Each type of "bulk" entity is assumed to be a world singleton.

    CONSTRUCT() = (this.chunks = Dict{v3i, GridChunk}())
    function DESTRUCT(is_entity_dying::Bool)
        if !is_entity_dying
            # Destroy all chunks.
            for chunk in collect(values(this.chunks))
                remove_component(entity, chunk)
            end
            # Destroy all bulk entities.
            for bulk_component in values(this.bulk_entities)
                remove_component(bulk_component.entity, bulk_component)
            end
        end
    end
end

function get_chunk_entity(chunk::GridChunk, chunk_id::v3i, world_grid_idx::v3i)::Optional{Union{Entity, BulkEntity}}
    local_grid_idx = chunk_grid_idx(chunk_id, world_grid_idx)
    element = chunk.elements[local_grid_idx]
    if element isa Entity
        return element
    elseif element isa BulkElements
        return (element, world_grid_idx)
    elseif isnothing(element)
        return nothing
    else
        error("Unexpected type: ", typeof(element))
    end
end

"Gets the chunk covering the given world position (if one exists)"
chunk_at(gm::GridManager, world_grid_pos::Vec3)::Optional{GridChunk} =
    get(gm.chunks, chunk_idx(world_grid_pos), nothing)
"Gets the entity (or bulk-entity) covering the grid cell at the given world position, if one exists"
entity_at(gm::GridManager, world_grid_pos::Vec3)::Optional{Union{Entity, BulkEntity}} = begin
    world_grid_idx = grid_idx(world_grid_pos)
    chunk_id = chunk_idx(world_grid_idx)
    chunk = chunk_at(gm, world_grid_idx)
    if isnothing(chunk)
        return nothing
    else
        return get_chunk_entity(chunk, chunk_id, world_grid_idx)
    end
end

"
Gets the chunk covering the given world position.
If none exists, a new one is generated and returned.
"
chunk_at!(gm::GridManager, world_grid_pos::Vec3)::GridChunk = begin
    chunk_id = chunk_idx(world_grid_pos)
    return get!(gm.chunks, chunk_id) do
        return add_component(gm.entity, GridChunk, chunk_id)
    end
end
"
Gets the entity (or bulk entity) covering the grid cell at the given world position.
If no chunk exists there, a new one is generated on-demand.
"
entity_at!(gm::GridManager, world_grid_pos::Vec3)::Optional{Union{Entity, BulkEntity}} = begin
    world_grid_idx = grid_idx(world_grid_pos)
    chunk_id = chunk_idx(world_grid_idx)
    chunk = chunk_at!(gm, world_grid_idx)
    return get_chunk_entity(chunk, chunk_id, world_grid_idx)
end
"
Gets the grid entity at the given location, and checks it for the given component.
Generates the relevant chunk if it doesn't exist yet.

Returns `nothing` if no entity is there, or the entity does not have that component,
    or the entity is a bulk-entity and `T` is not its data-type.
"
function component_at!(gm::GridManager, world_grid_pos::Vec3, ::Type{T})::Optional{T} where {T}
    entity = entity_at!(gm, world_grid_pos)
    if isnothing(entity)
        return nothing
    elseif entity isa Entity
        return get_component(entity, T)::Optional{T}
    elseif entity isa BulkEntity
        data = bulk_data_at(entity...)
        if data isa T
            return data
        else
            return nothing
        end
    end
end

"Adds to the world the given element from a bulk-entity"
function add_bulk_entity!(gm::GridManager, world_grid_pos::Vec3,
                          bulk::BulkElements{T}, data::T) where {T}
    world_grid_idx = grid_idx(world_grid_pos)
    chunk_id = chunk_idx(world_grid_idx)
    chunk_relative_idx = chunk_grid_idx(chunk_id, world_grid_idx)

    chunk = chunk_at!(gm, world_grid_idx)

    chunk.elements[chunk_relative_idx] = bulk
    bulk_create_at(bulk, world_grid_idx, data)

    return nothing
end
"
Removes a bulk-entity from the world at the given grid position.
"
function remove_bulk_entity!(gm::GridManager, world_grid_pos::Vec3)::Nothing
    # Do some coordinate math.
    world_grid_idx = grid_idx(world_grid_pos)
    chunk_id = chunk_idx(world_grid_idx)
    local_grid_idx = chunk_grid_idx(chunk_id, world_grid_idx)

    # Get the element at the grid position.
    chunk = gm.chunks[chunk_id]
    element = chunk.elements[local_grid_idx]
    @bp_check(element isa BulkElements,
              "Expected a bulk component at ", world_grid_pos, " but got a ", typeof(element))

    # Destroy it.
    chunk.elements[local_grid_idx] = nothing
    bulk_destroy_at(element, world_grid_idx)
    return nothing # Returning the destroyed data would be nice,
                   #    but creates unavoidable type-instability
end