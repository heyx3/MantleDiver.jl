# Specifies different kinds of entities and how to interact with them.

##   Grid   ##

function make_grid(world::World)::Entity
    entity = add_entity(world)

    grid = add_component(GridManagerComponent, entity)

    return entity
end


##   Player   ##

function make_player(world::World, pos::v3f)::Entity
    entity = add_entity(world)

    pos = add_component(ContinuousPosition, entity, pos)
    debug_visuals = add_component(DebugGuiVisualsComponent_DrillPod, entity)

    return entity
end

"Gets whether the player is busy moving, drilling, etc. and cannot take new actions right now"
function player_is_busy(player::Entity)::Bool
    return has_component(player, CabMovementComponent) ||
           has_component(player, CabDrillComponent)
end

function player_start_turning(player::Entity, target_heading::Union{fquat, v3f})
    if target_heading isa v3f
        return player_start_turning(player, fquat(get_horz_vector(1), target_heading))
    elseif target_heading isa fquat
        return add_component(CabTurnComponent, player, target_heading)
    else
        error(typeof(target_heading))
    end
end
function player_start_moving(player::Entity,
                             movement::CabMovement,
                             direction::CabMovementDir)
    @bp_check(
        begin
            grid = get_component(player.world, GridManagerComponent)[1].entities
            grid_idx_range = Box(
                min=one(v3i),
                size=vsize(grid)
            )
            is_legal(
                movement, direction,
                get_voxel_position(player),
                grid_pos -> is_touching(grid_idx_range, grid_pos) && isnothing(grid[grid_pos])
            )
        end,
        "Trying to do illegal move: ", movement, " in ", direction
    )
    return add_component(CabMovementComponent, player, movement, direction)
end
function player_start_drilling(player::Entity,
                               direction::GridDirection,
                               fx_seed::Float32 = rand(Float32))
    @bp_check(
        begin
            grid = get_component(player.world, GridManagerComponent)[1].entities
            grid_idx_range = Box(
                min=one(v3i),
                size=vsize(grid)
            )
            drilled_pos = get_voxel_position(player) + grid_vector(direction)
            is_touching(grid_idx_range, drilled_pos) && isnothing(grid[drilled_pos])
        end,
        "Trying to do an illegal drill: ",
          "from ", get_voxel_position(player), " along direction ", direction
    )
    return add_component(CabDrillComponent, player, direction, fx_seed)
end


##   Rocks   ##

function make_rock(world::World, pos::v3i, is_gold::Bool)::Entity
    entity = add_entity(world)

    pos = add_component(DiscreteVoxelPosition, entity, pos)
    debug_visuals = add_component(DebugGuiVisualsComponent_Rock, entity)
    grid_element = add_component(GridElementComponent, entity)
    gold_marker = if is_gold
        add_component(GoldComponent, entity)
    else
        nothing
    end

    return entity
end