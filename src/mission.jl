"A single game session"
mutable struct Mission
    ecs::ECS.World
    grid::GridManager

    loadout::PlayerLoadout
    player::Entity
    player_pos::ContinuousPosition

    function Mission(loadout::PlayerLoadout
                     ;
                     seed::UInt = rand(UInt))
        PLAYER_START_POS = v3i(0, 0, 0)

        @d8_debug println(stderr, "Seed used: ", seed)
        Random.seed!(seed)

        world = ECS.World()
        grid = let entity = make_grid(world, MainGenerator,
                                      rand(UInt32),
                                      PLAYER_START_POS,
                                      5, 0.39,
                                      3, 0.28, 2.4)
            get_component(entity, GridManager)
        end

        player = make_player(world, PLAYER_START_POS)
        check_for_fall(player, grid)

        return new(world, grid, loadout,
                   player, get_component(player, ContinuousPosition))
    end
end

"Updates the world, and returns whether the mission is still ongoing"
function tick!(mission::Mission, delta_seconds::Float32)::Bool
    ECS.tick_world(mission.ecs, delta_seconds)

    # Make sure chunks near the player are all generated.
    player_voxel_pos = get_voxel_position(mission.player)
    for corner in -1:one(v3i)
        chunk_at!(mission.grid, player_voxel_pos + (corner * CHUNK_SIZE))
    end

    return true
end