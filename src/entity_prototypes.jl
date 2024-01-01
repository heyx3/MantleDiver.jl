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
                               fx_seed::Float32 = rand(Float32))
    @d8_assert(
        exists(component_at!(get_component(player.world, GridManager)[1],
                             get_voxel_position(player) + grid_vector(direction, Int32),
                             Rock)),
        "Trying to do an illegal drill: ",
          "from ", get_voxel_position(player), " along direction ", direction
    )
    return add_component(player, CabDrill, direction, fx_seed)
end


##   Rocks   ##

function make_rock(world::World, grid_pos::Vec3{<:Integer},
                   mineral_amounts::PerMineral{Float32})::Entity
    entity = add_entity(world)

    pos_component = add_component(entity, DiscretePosition, grid_pos)
    debug_visuals = add_component(entity, DebugGuiVisuals_Rock)
    grid_element = add_component(entity, GridElement)
    rock = add_component(entity, Rock, mineral_amounts)

    return entity
end