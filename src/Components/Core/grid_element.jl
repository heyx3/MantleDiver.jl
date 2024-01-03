@component GridElement {entitySingleton} {require: DiscretePosition} begin
    # Whether this element blocks movement.
    is_solid::Bool

    function CONSTRUCT(is_solid::Bool = false,
                       new_pos::Optional{v3i} = nothing
                       ;
                       grid::GridManager = get_component(world, GridManager)[1],
                       chunk::Optional{GridChunk} = nothing)
        this.is_solid = is_solid

        # Get or set the position as instructed by the user.
        pos::v3i = if exists(new_pos)
            get_component(entity, DiscretePosition).pos = new_pos
            new_pos
        else
            get_component(entity, DiscretePosition).pos
        end

        # Register this element with the grid.
        # If no chunk exists, it's because we're in the middle of generating it,
        #    so we don't need to manually register.
        if isnothing(chunk)
            chunk = chunk_at(grid, pos)
        end
        if exists(chunk)
            chunk_relative_idx = chunk_grid_idx(chunk.idx, pos)
            @bp_check(isnothing(chunk.elements[chunk_relative_idx]),
                      "A grid element already exists at ", pos)
            chunk.elements[chunk_relative_idx] = entity
        end
    end
    function DESTRUCT()
        # Unregister this element with the grid.
        # Watch out for the case in which the entire world is dying.
        grid_data = get_component(world, GridManager)
        if exists(grid_data)
            (grid, _) = grid_data
            world_grid_idx::v3i = get_component(entity, DiscretePosition).pos
            chunk = chunk_at(grid, world_grid_idx)
            if exists(chunk)
                chunk_relative_idx = chunk_grid_idx(chunk.idx, world_grid_idx)
                @bp_check(chunk.elements[chunk_relative_idx] == entity,
                        "Entity is not registered at its own voxel position ", world_grid_idx)
                chunk.elements[chunk_relative_idx] = nothing
            end
        end
    end
end

function is_passable(gm::GridManager, world_grid_pos::Vec3)::Bool
    entity = entity_at!(gm, world_grid_pos)
    if entity isa Entity
        grid_el::GridElement = get_component(entity, GridElement)
        return !grid_el.is_solid
    elseif entity isa BulkEntity
        return entity[1].is_passable(entity[2])
    elseif isnothing(entity)
        return true
    else
        error("Unknown type: ", typeof(entity))
    end
end