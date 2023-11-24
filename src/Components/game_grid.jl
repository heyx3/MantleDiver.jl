##   Manager   ##

@component GridManager {worldSingleton} begin
    entities::Array{Optional{ECS.Entity}, 3}

    function CONSTRUCT(size::Vec3{<:Integer})
        this.entities = Array{Optional{ECS.Entity}, 3}(nothing, size...)
    end
end


##   Element   ##

@component GridElement {entitySingleton} {require: DiscretePosition} begin
    function CONSTRUCT(new_pos::Optional{v3i} = nothing)
        # Get or set the position as instructed by the user.
        pos::v3i = if exists(new_pos)
            get_component(entity, DiscretePosition).pos = new_pos
            new_pos
        else
            get_component(entity, DiscretePosition).pos
        end

        # Register this element with the grid.
        (grid, grid_entity) = get_component(world, GridManager)
        @bp_check(isnothing(grid.entities[pos]), "A grid element already exists at ", pos)
        grid.entities[pos] = entity
    end
    function DESTRUCT()
        # Unregister this element with the grid.
        # Watch out for the case where the grid itself is dying (i.e. the world is ending).
        grid_data = get_component(world, GridManager)
        if exists(grid_data)
            (grid, grid_entity) = grid_data
            pos = get_voxel_position(entity)
            @bp_check(grid.entities[pos] == entity,
                      "Entity is not registered at its own voxel position ", pos)
            grid.entities[pos] = nothing
        end
    end
end