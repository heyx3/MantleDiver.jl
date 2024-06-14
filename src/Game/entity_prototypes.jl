# Specifies different kinds of entities and how to interact with them.

##   Grid   ##

function make_grid(world::World,
                   generator::Type{<:GridGenerator},
                   generator_args...)::Entity
    entity = add_entity(world)

    grid = add_component(entity, GridManager)
    generator = add_component(entity, generator, generator_args...)

    return entity
end


##   Player   ##

function make_player(world::World, pos::Vec3)::Entity
    entity = add_entity(world)

    pos_component = add_component(entity, ContinuousPosition, convert(v3f, pos))
    orientation_component = add_component(entity, WorldOrientation)
    debug_visuals = add_component(entity, DebugGuiVisuals_DrillPod,
        vRGBAf(0.2, 1, 0.5, 1),
        @f32(10),
        @f32(3),

        vRGBAf(1, 0.7, 0.7, 1),
        @f32(15),
        @f32(3)
    )

    return entity
end

"Gets whether the player is busy moving, drilling, etc. and cannot take new actions right now"
function player_is_busy(player::Entity)::Bool
    return has_component(player, Maneuver)
end

function player_start_turning(player::Entity, target_heading::Union{fquat, v3f})
    if target_heading isa v3f
        return player_start_turning(player, fquat(get_horz_vector(1), target_heading))
    elseif target_heading isa fquat
        return add_component(player, CabTurn, target_heading)
    else
        error(typeof(target_heading))
    end
end
function player_start_moving(player::Entity,
                             movement::CabMovementData,
                             direction::CabMovementDir)
    @bp_check(
        begin
            grid = get_component(player.world, GridManager)[1]
            is_legal(
                movement, direction,
                get_voxel_position(player),
                grid_pos -> is_passable(grid, grid_pos)
            )
        end,
        "Trying to do illegal move: ", movement, " in ", direction
    )
    return add_component(player, CabMovement, movement, direction)
end
function player_start_drilling(player::Entity,
                               direction::GridDirection,
                               fx_seed::Float32 = rand(Float32)
                              )::Optional{CabDrill}
    grid = get_component(player.world, GridManager)[1]
    grid_pos = get_voxel_position(player) + grid_vector(direction, Int32)
    grid_entity = entity_at!(grid, grid_pos)
    if isnothing(grid_entity)
        @error "Tried to drill empty space at $grid_pos. Drilling will not happen."
        return nothing
    end

    drill_response = get_drill_response(grid_entity)
    if isnothing(drill_response)
        @error "Grid element at $grid_pos doesn't exist or has no DrillResponse! Drilling will not happen."
        return nothing
    end
    if !drill_response.can_be_drilled(grid_pos, player)
        return nothing
    end
    drill_response.start_drilling(grid_pos, player)

    return add_component(player, CabDrill, direction, fx_seed)
end

function can_do_move_from(player_grid_idx::v3i,
                          dir::CabMovementDir,
                          move::CabMovementData,
                          grid::GridManager
                         )::Bool
    return is_legal(move, dir, player_grid_idx, pos->is_passable(grid, pos))
end
function can_drill_from(player_grid_idx::v3i,
                        player_dir::CabMovementDir,
                        drill_canonical_dir::Vec3,
                        grid::GridManager)
    world_dir::v3f = rotate_cab_movement(convert(v3f, drill_canonical_dir), player_dir)
    drilled_pos::v3f = player_grid_idx + world_dir
    drilled_grid_idx::v3i = grid_idx(drilled_pos)
    drilled_entity = component_at!(grid, drilled_grid_idx, Rock) #TODO: Drillable component for grid entities
    return exists(drilled_entity)
end


##   Rocks   ##

"
NOTE: Only registers the rock with the bulk grid entity, not with the chunks!
So this should only be called from the level's Generator component.
"
function make_rock(world::World, grid_pos::Vec3{<:Integer}, data::Rock;
                   grid::GridManager = get_component(world, GridManager)[1]
                  )::BulkEntity{RockBulkElements}
    # Get or make the bulk grid element for rocks.
    rocks = let found = get_component(world, RockBulkElements)
        if exists(found)
            found[1]
        else
            en = add_entity(world)
            add_component(en, DebugGuiVisuals_Rocks)
            add_component(en, Renderable_Rock)

            get_component(en, RockBulkElements)
        end
    end

    bulk_create_at(rocks, grid_pos, data)
    return (rocks, grid_pos)
end