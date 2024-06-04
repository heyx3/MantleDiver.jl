"A single game session"
mutable struct Mission
    ecs::ECS.World
    grid::GridManager

    loadout::PlayerLoadout
    player::Entity
    player_pos::ContinuousPosition
    player_rot::WorldOrientation
    player_viewport::WorldViewport
    player_camera_ubo::GL.Buffer

    buffer_renderables::Vector{Renderable}

    function Mission(loadout::PlayerLoadout,
                     player_view_resolution::v2i
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

        cam_ubo = Buffer(true, CameraDataBuffer)

        return new(
            world, grid,
            loadout, player,
            get_component.(Ref(player), (
                ContinuousPosition,
                WorldOrientation
            ))...,
            WorldViewport(player_view_resolution), cam_ubo,
            Vector{Renderable}()
        )
    end
end

function Base.close(mission::Mission)
    reset_world(mission.ecs) # To ensure components' resources are released
    close(mission.player_viewport)
    close(mission.player_camera_ubo)
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

"
Renders the mission into the player's viewport.
You may display this viewport with `post_process_framebuffer(mission.player_viewport)`.
"
function render_mission(mission::Mission, assets::Assets, settings::ViewportDrawSettings)
    # Collect renderables.
    empty!(mission.buffer_renderables)
    append!(mission.buffer_renderables, (c for (c, e) in get_components(mission.ecs, Renderable)))
    #TODO: Pre-sort by depth?

    render_data = WorldRenderData(
        mission.player_viewport
    )

    # Set up the player camera data buffer.
    #TODO: Re-use a CameaDataBuffer instance so we're not constantly allocating it.
    GL.set_buffer_data(mission.player_camera_ubo, CameraDataBuffer(Bplus.Cam3D{Float32}(
        pos = mission.player_pos.pos,
        forward = q_apply(mission.player_rot.rot, WORLD_FORWARD),
        up = q_apply(mission.player_rot.rot, WORLD_UP),
        projection = PerspectiveProjection{Float32}(
            clip_range = IntervalF(min=0.05, max=1000),
            fov_degrees = 90,
            aspect_width_over_height = 1
        )
    )))
    GL.set_uniform_block(mission.player_camera_ubo, UBO_INDEX_CAM_DATA)

    # Render into the main framebuffer.
    render_view(mission.player_viewport, assets, settings, output) do pass::E_RenderPass
        for renderable in mission.buffer_renderables
            renderable.render(render_data)
        end
        return nothing # output of render() is type-unstable, so don't return it
    end
end