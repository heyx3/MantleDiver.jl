# Certain things in the game world (mostly rocks) are organized into a uniform grid.
# This grid is managed in chunks; new chunks are generated as the player goes deeper.
# Chunks' initial elements are filled in by a GridGenerator.
# The chunks, manager, and generator all live on a single entity.

##  GridGenerator  ##

@component GridGenerator {abstract} {worldSingleton} begin
    @promise generate(world_grid_idx::v3i)::Optional{Entity}
end


##   Chunk   ##

const CHUNK_SIZE = v3i(8, 8, 8)
const ChunkElementGrid{T} = SizedArray{Tuple{Int.(CHUNK_SIZE)...}, T, 3,
                                       3, Array{T, 3}}

@component GridChunk {require: GridGenerator} begin
    idx::v3i # Multiply by the chunk size to get the first grid index in this chunk
    elements::ChunkElementGrid{Optional{Entity}}

    function CONSTRUCT(idx::v3i)
        this.idx = idx
        first_world_idx::v3i = this.idx * CHUNK_SIZE

        # Fill in the chunk array using this world's generator.
        # Dispatch to a function where the generator type is known at compile-time.
        function generate_chunk(gen::T) where {T<:GridGenerator}
            [gen.generate(first_world_idx + v3i(x, y, z) - Int32(1))
                 for x in 1:CHUNK_SIZE.x,
                     y in 1:CHUNK_SIZE.y,
                     z in 1:CHUNK_SIZE.z]
        end
        this.elements = generate_chunk(get_component(entity, GridGenerator))
    end
    function DESTRUCT(is_world_grid_dying::Bool)
        # Kill all grid entities within this chunk.
        for element in this.elements
            if exists(element)
                remove_entity(world, element)
            end
        end
        # Un-register this chunk with the manager component.
        if !is_world_grid_dying
            grid = get_component(entity, GridManager)
            delete!(grid.chunks, this.idx)
        end
    end
end

@inline chunk_region(ch::GridChunk) = Box3Di(
    min = ch.idx * CHUNK_SIZE,
    size = CHUNK_SIZE
)
function chunk_idx(world_grid_pos::Vec3)
    i = grid_idx(world_grid_pos) # If continuous, turn into voxel
    return vselect(
        i ÷ CHUNK_SIZE,
        (i - CHUNK_SIZE + Int32(1)) ÷ CHUNK_SIZE,
        i < 0
    )
end
function chunk_relative_pos(chunk_idx::v3i, world_grid_pos::Vec3)
    world_grid_pos - (chunk_idx * CHUNK_SIZE)
end


##   Manager of chunks   ##

@component GridManager {worldSingleton} begin
    chunks::Dict{v3i, GridChunk}

    CONSTRUCT() = (this.chunks = Dict{v3i, GridChunk}())
    function DESTRUCT()
        # Destroy all chunks.
        for chunk in collect(values(this.chunks))
            remove_component(entity, chunk)
        end
    end
end

"Gets the chunk covering the given world position (if one exists)"
chunk_at(gm::GridManager, world_grid_pos::Vec3)::Optional{GridChunk} =
    get(gm.chunks, chunk_idx(world_grid_pos), nothing)
"Gets the entity covering the grid cell at the given world position (if one exists)"
entity_at(gm::GridManager, world_grid_pos::Vec3)::Optional{Entity} = begin
    world_grid_idx = grid_idx(world_grid_pos)
    chunk_id = chunk_idx(world_grid_idx)
    chunk = chunk_at(gm, chunk_id)
    if isnothing(chunk)
        return nothing
    end

    chunk_grid_idx = 1 + chunk_relative_pos(chunk_id, world_grid_idx)
    return chunk.elements[chunk_grid_idx]
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
Gets the entity covering the grid cell at the given world position.
If no chunk exists there, a new one is generated on-demand.
"
entity_at!(gm::GridManager, world_grid_pos::Vec3)::Optional{Entity} = begin
    world_grid_idx = grid_idx(world_grid_pos)
    chunk_id = chunk_idx(world_grid_idx)
    chunk = chunk_at!(gm, world_grid_pos)

    chunk_grid_idx = 1 + chunk_relative_pos(chunk_id, world_grid_idx)
    return chunk.elements[chunk_grid_idx]
end
"
Gets the grid entity at the given location, and checks it for the given component.
Generates the relevant chunk if it doesn't exist yet.

Returns `nothing` if no entity is there, or the entity does not have that component.
"
function component_at!(gm::GridManager, world_grid_pos::Vec3, ::Type{T})::Optional{T} where {T<:AbstractComponent}
    entity = entity_at!(gm, world_grid_pos)
    if isnothing(entity)
        return nothing
    else
        return get_component(entity, T)::Optional{T}
    end
end