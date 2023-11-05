##   Manager   ##

mutable struct GridManagerComponent <: AbstractComponent
    entities::Array{Optional{ECS.Entity}, 3}

    GridManagerComponent(size::Vec3{<:Integer}) = new(Array{Optional{ECS.Entity}, 3}(nothing, size...))
end
ECS.allow_multiple(::Type{GridManagerComponent}) = false


##   Element   ##

mutable struct GridElementComponent <: AbstractComponent end
ECS.require_components(::Type{GridElementComponent}) = (DiscreteVoxelPosition, )
ECS.allow_multiple(::Type{GridElementComponent}) = false

function ECS.create_component(::Type{GridElementComponent}, entity::Entity,
                              args...
                              ;
                              # If provided, the rock's position component will be set to this value.
                              new_pos::Optional{v3i} = nothing,
                              kw_args...)
    # Get and/or set this entity's voxel grid position.
    pos_component = get_component(entity, DiscreteVoxelPosition)
    pos::v3i = if exists(new_pos)
        pos_component.pos = new_pos
        new_pos
    else
        pos_component.pos
    end

    # Set up the component.
    grid_element = GridElementComponent(args...; kw_args...)

    # Register it with the grid.
    (grid, grid_entity) = get_component(entity.world, GridManagerComponent)
    @bp_check(isnothing(grid.entities[pos]), "A grid element already exists at ", pos)
    grid.entities[pos] = entity

    return grid_element
end
function ECS.destroy_component(el::GridElementComponent, entity::Entity, is_dying::Bool)
    pos::v3i = get_voxel_position(entity)

    # Unregister this rock with the grid.
    # Watch out for the case where the grid itself is dying (i.e. the world is ending).
    grid_data = get_component(entity.world, GridManagerComponent)
    if exists(grid_data)
        (grid, grid_entity) = grid_data
        @bp_check(grid.entities[pos] == entity,
                  "Entity is not registered at its own voxel position ", pos)
        grid.entities[pos] = nothing
    end

    return nothing
end