"A single game session"
mutable struct Mission
    ecs::Bplus.ECS.World
    grid::GridManager
    ecs_services::Services

    loadout::PlayerLoadout
    player::Cab
    player_viewport::WorldViewport
    player_camera_ubo::GL.Buffer

    ambient_sound_loop::PlayingLoop

    buffer_renderables::Vector{Renderable}

    function Mission(loadout::PlayerLoadout,
                     player_view_resolution::v2i,
                     audio::AudioManager,
                     audio_files::AudioFiles,
                     assets::Assets
                     ;
                     seed::UInt = @d8_debug(0x123345678911, rand(UInt)))
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
        services = let entity = add_entity(world)
            add_component(entity, Services,
                          audio, audio_files, assets)
        end

        player = make_player(world, PLAYER_START_POS, loadout)
        cab = get_component(player, Cab)
        check_for_fall(cab, grid)

        cam_ubo = Buffer(true, CameraDataBuffer)

        # Set up a segmentation rectangle.
        segment_border = v2i(3, 3)
        segment_lengths = v3i((player_view_resolution - 4)..., 0)
        segment_min = segment_border - 1
        segment_max = player_view_resolution + 1 - segment_border
        segment_bounds = vappend(segment_min, segment_max)
        segment_lines = [
            # Outer border
            SegmentationLine(v2i(0, 0), v2i(player_view_resolution.x, 0)),
            SegmentationLine(v2i(player_view_resolution.x, 0), v2i(0, player_view_resolution.y)),
            SegmentationLine(player_view_resolution, v2i(-player_view_resolution.x, 0)),
            SegmentationLine(v2i(0, player_view_resolution.y), v2i(0, -player_view_resolution.y)),

            # Inner border
            SegmentationLine(segment_bounds.xy, segment_lengths.zy),
            SegmentationLine(segment_bounds.xw, segment_lengths.xz),
            SegmentationLine(segment_bounds.zw, -segment_lengths.zy),
            SegmentationLine(segment_bounds.zy, -segment_lengths.xz)
        ]

        # Set up an interface.
        player_interface = Interface(Panel[
            Panel(WidgetRing, player_view_resolution, [
                WidgetRingLayer(
                    CharDisplayValue(
                        foreground = CharForegroundValue('X'),
                        background = CharBackgroundValue(0, 1)
                    )
                ),
                WidgetRingLayer(
                    corners=CharDisplayValue(
                        foreground = CharForegroundValue('O'),
                        background = CharBackgroundValue(0, 1)
                    ),
                    edges_horizontal=CharDisplayValue(
                        foreground = CharForegroundValue('-')
                    ),
                    edges_vertical =CharDisplayValue(
                        foreground = CharForegroundValue('|', 1, true),
                        background = CharBackgroundValue(0, 1)
                    )
                )
            ])
        ])

        ambient_sound_loop = play_loop(
            audio,
            audio_files.ambiance_plain,
            audio_files.crossfade_seconds_ambiance_plain
        )

        return new(
            world, grid, services,
            loadout, cab,
            WorldViewport(
                player_view_resolution,
                segment_lines,
                player_interface
            ),
            cam_ubo,
            ambient_sound_loop,
            Vector{Renderable}()
        )
    end
end

function Base.close(mission::Mission)
    reset_world(mission.ecs) # To ensure components' resources are released
    @atomic(mission.ambient_sound_loop.should_stop = true)
    close(mission.player_viewport)
    close(mission.player_camera_ubo)
end

"Updates the world, and returns whether the mission is still ongoing"
function tick!(mission::Mission, delta_seconds::Float32)::Bool
    ECS.tick_world(mission.ecs, delta_seconds)

    # Make sure chunks near the player are all generated.
    player_voxel_pos = mission.player.pos_component.get_voxel_position()
    for corner in -1:one(v3i)
        chunk_at!(mission.grid, player_voxel_pos + (corner * CHUNK_SIZE))
    end

    # Update the player's viewport.
    let int = mission.player_viewport.interface
        if exists(int)
            update_interface!(int, delta_seconds, mission.player_viewport.resolution)
        end
    end

    # For now, the mission never ends.
    return true
end


@kwdef mutable struct MissionDrawSettings
    enable_world::Bool = true # Disables world but not interface/segmentation rendering
end

"
Renders the mission into the player's viewport.
You may display this viewport with `post_process_framebuffer(mission.player_viewport, ...)`.
"
function render_mission(mission::Mission, assets::Assets,
                        mission_settings::MissionDrawSettings,
                        viewport_settings::ViewportDrawSettings)
    @d8_debug(@check_gl_logs "Before rendering into framebuffer")

    # Collect renderables.
    empty!(mission.buffer_renderables)
    append!(mission.buffer_renderables, (c for (c, e) in get_components(mission.ecs, Renderable)))
    #TODO: Pre-sort by depth per-viewport?

    # Set up the player camera data buffer.
    #TODO: The viewport should have a world position/orientation and projection settings, and set up this UBO right before rendering.
    #TODO: Re-use a CameraDataBuffer instance so we're not constantly allocating it.
    p_pos = get_cosmetic_pos(mission.player.entity)
    p_rot = get_cosmetic_rot(mission.player.entity)
    GL.set_buffer_data(mission.player_camera_ubo, CameraDataBuffer(Bplus.Cam3D{Float32}(
        pos = p_pos,
        forward = q_apply(p_rot, WORLD_FORWARD),
        up = q_apply(p_rot, WORLD_UP),
        projection = Bplus.PerspectiveProjection{Float32}(
            clip_range = IntervalF(min=0.05, max=1000),
            vertical_fov_degrees = 90,
            aspect_width_over_height = 1
        )
    )))
    GL.set_uniform_block(mission.player_camera_ubo, UBO_INDEX_CAM_DATA)

    # Render into the player's viewport.
    render_data = WorldRenderData(
        mission.player_viewport
    )
    render_to_framebuffer(mission.player_viewport, assets, viewport_settings) do pass::E_RenderPass
        if mission_settings.enable_world
            for renderable in mission.buffer_renderables
                renderable.render(render_data)
                @d8_debug(@check_gl_logs "After rendering " typeof(renderable))
            end
        end
        # Make sure nothing type-unstable is returned.
        return nothing
    end

    @d8_debug(@check_gl_logs "After rendering into framebuffer")
end