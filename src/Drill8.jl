module Drill8

IS_PRECOMPILING::Bool = true # Gets set to false at the bottom of this file

using Random, Setfield

using CImGui, GLFW, FreeType, ImageIO, FileIO,
      CSyntax, StaticArrays

using Bplus; @using_bplus

# Reconfigure B+'s coordinate system to match Dear ImGUI.
# Bplus.BplusCore.Math.get_right_handed() = false
const WORLD_FORWARD = v3f(1, 0, 0)
const WORLD_RIGHT = v3f(0, -1, 0)
const WORLD_UP = v3f(0, 0, 1)

const PI2 = Float32(2π)

# Define @d8_assert and @d8_debug
Bplus.@make_toggleable_asserts d8_


include("Renderer/shader_utils.jl")
include("Renderer/chars.jl")
include("Renderer/segmentation.jl")
include("Renderer/framebuffer.jl")
include("Renderer/assets.jl")
include("Renderer/interface.jl")
include("Renderer/world_viewport.jl")

include("Audio/audio.jl")

include("InterfaceWidgets/image.jl")
include("InterfaceWidgets/text.jl")
include("InterfaceWidgets/ring.jl")
include("InterfaceWidgets/control_map.jl")

include("Components/Core/services.jl")
include("Components/Core/transforms.jl")
include("Components/Core/grid_data.jl")
include("Components/Core/grid_event_responders.jl")
include("Components/Core/grid_element_bulk.jl")
include("Components/Core/grid_manager.jl")
include("Components/Core/grid_element.jl")
include("Components/Core/debug_gui_visuals.jl")
include("Components/Core/renderable.jl")
include("Components/GridObjects/rock.jl")

include("PlayerCab/data.jl")
include("PlayerCab/maneuvers.jl")
include("PlayerCab/rendering.jl")

include("Game/entity_prototypes.jl")
include("Game/level_generators.jl")
include("Game/mission.jl")
include("Game/input.jl")

include("Debug/debug_assets.jl")
include("Debug/debug_gui_widgets.jl")


get_imgui_current_drawable_region() = Box2Df(
    #TODO Handle scroll offset, then move this function into Bplus.GUI
    min = convert(v2f, CImGui.GetCursorPos()) -
            convert(v2f, CImGui.GetWindowPos()),
    size = convert(v2f, CImGui.GetContentRegionAvail())
)

"
Runs the game.
In 'auto mode', plays the game with no fps cap and automatic maneuvers,
    to precompile as much as possible.
"
function inner_main(auto_mode_frame_count::Optional{Int})::Cint
    auto_mode::Bool = exists(auto_mode_frame_count)
    return Bplus.@game_loop(begin
        INIT(
            @d8_debug(v2i(900, 950), v2i(900, 900)),
            "Drill8",
            debug_mode = @d8_debug,
            vsync = (auto_mode ? VsyncModes.off : VsyncModes.on)
        )

        SETUP = begin
            # Make sure we're running from the project folder (or equivalent built executable folder).
            if !isdir(ASSETS_FOLDER)
                error("Running from a location with no 'assets' folder! ",
                        "This is not the right place to run from. ",
                        pwd())
            end

            # Single-threaded runtimes will experience audio problems.
            # When compiling this module we run an auto-play instance of the game,
            #    and it's apparently always single-threaded.
            if !IS_PRECOMPILING && (Threads.nthreads() < 2)
                @warn string(
                    "Running Julia single-threaded; this usually causes audio problems. ",
                    "Try running with '-t auto' or at least '-t 2'."
                )
            end

            # Set up audio.
            audio_files = AudioFiles()
            audio_manager = AudioManager{2, Float32}(SampledSignals.samplerate(audio_files.drill.buffers))
            if IS_PRECOMPILING
                audio_manager.disable_new_sounds = true
            end

            # Set up graphics assets.
            assets = Assets()
            @d8_debug(@check_gl_logs "After asset creation")

            # Start a mission.
            mission = Mission(
                if auto_mode || @d8_debug()
                    maxed_loadout()
                else
                    PlayerLoadout()
                end,
                v2i(50, 50),
                audio_manager, audio_files, assets
            )
            @d8_debug(@check_gl_logs "After mission creation")
            register_mission_inputs()

            # In debug builds provide various GUI widgets,
            #    one of which will contain the rendered scene.
            @d8_debug begin
                debug_assets = DebugAssets()
                @check_gl_logs "After DebugAssets creation"
                debug_gui = DebugGui()
                @check_gl_logs "After DebugGui creation"
                debug_game_render = GL.Target(
                    convert(v2u, mission.player_viewport.resolution * 16),
                    GL.SimpleFormat(
                        GL.FormatTypes.normalized_uint,
                        GL.SimpleFormatComponents.RGB,
                        GL.SimpleFormatBitDepths.B8
                    ),
                    GL.DepthStencilFormats.depth_16u
                )
                @check_gl_logs "After DebugGameRender creation"

                is_in_main_view::Bool = false
            end

            if auto_mode
                LOOP.max_fps = nothing
                println(stderr, "Running an auto-game of ", auto_mode_frame_count, " frames...")
            end

            GLFW.ShowWindow(LOOP.context.window)
        end

        LOOP = begin
            @d8_debug(@check_gl_logs "Start of iteration " LOOP.frame_idx)
            if GLFW.WindowShouldClose(LOOP.context.window)
                break
            end

            # Tick the mission, and quit if it ends.
            delta_seconds::Float32 = auto_mode ? @f32(1/30) : LOOP.delta_seconds
            continue_mission::Bool = if !@d8_debug
                tick!(mission, delta_seconds)
            else
                if debug_gui.gameplay_speed == DebugGuiSpeed.play
                    tick!(mission, delta_seconds)
                elseif debug_gui.gameplay_speed == DebugGuiSpeed.pause
                    true
                elseif debug_gui.gameplay_speed == DebugGuiSpeed.fast_forward
                    b = true
                    for i in 1:debug_gui.fast_forward_speed
                        b |= tick!(mission, delta_seconds)
                        (!b) && break
                    end
                    b
                else
                    error("Unhandled case: ", debug_gui.gameplay_speed)
                end
            end
            @d8_debug(@check_gl_logs "After mission tick")
            (!continue_mission) && break

            # Handle mission inputs.
            if @d8_debug is_in_main_view true
                update_mission_inputs(mission)
            end

            # Render the player's POV.
            player_viewport_settings = @d8_debug debug_gui.viewport_draw_settings ViewportDrawSettings(
            )
            mission_draw_settings = @d8_debug debug_gui.mission_draw_settings MissionDrawSettings(
            )
            render_mission(mission, assets, mission_draw_settings, player_viewport_settings)
            @d8_debug(@check_gl_logs "After mission render")

            # Draw the game to the screen (or to a Target in debug builds).
            @d8_debug begin
                GL.target_clear(debug_game_render, vRGBAf(1, 0, 1, 0))
                target_activate(debug_game_render)
            end begin
                GL.clear_screen(vRGBAf(1, 0, 1, 0))
            end
            post_process_framebuffer(mission.player_viewport, assets, player_viewport_settings)
            @d8_debug target_activate(nothing)
            @d8_debug(@check_gl_logs "After mission post-processing")

            # Draw the debugging GUI.
            @d8_debug begin
                screen_size = convert(v2f, GL.get_window_size())
                CImGui.SetNextWindowPos(v2i(0, 0))
                CImGui.SetNextWindowSize(screen_size)
                GUI.gui_window("#MainWnd", C_NULL, CImGui.LibCImGui.ImGuiWindowFlags_NoDecoration) do
                    gui_game_speed(debug_gui, debug_assets)

                    # Draw the tabs.
                    gui_tab_views("#DebugTabs") do

                        @check_gl_logs "Before any debug GUI tabs"

                        gui_tab_item("Game View") do
                            is_in_main_view = true
                            gui_debug_main_view(debug_gui, mission, debug_game_render)
                        end
                        @check_gl_logs "After 'Game View' tab"

                        gui_tab_item("Debug Game View") do
                            is_in_main_view = false

                            game_view_tab_region = get_imgui_current_drawable_region()
                            game_view_area = Box2Df(
                                min=min_inclusive(game_view_tab_region),
                                size=size(game_view_tab_region) * v2f(1, 0.8)
                            )

                            CImGui.Dummy(size(game_view_area)...)
                            gui_debug_game_views(game_view_area, mission, debug_gui)

                            GUI.gui_within_fold("Initial loadout") do
                                # Don't allow this one to actually be edited.
                                # Unfortunately we need a newer Dear ImGUI to actually disable the GUI.
                                gui_debug_loadout(copy(mission.loadout), debug_gui)
                            end
                            GUI.gui_within_fold("Current loadout") do
                                gui_debug_loadout(mission.player.loadout, debug_gui)
                            end
                        end
                        @check_gl_logs "After 'Debug Game View' tab"

                        gui_tab_item("Assets") do
                            is_in_main_view = false

                            gui_visualize_textures(debug_gui, debug_assets, mission, assets)
                        end
                        @check_gl_logs "After 'Assets' tab"

                        gui_tab_item("OpenGL resources") do
                            is_in_main_view = false

                            gui_visualize_resources(debug_gui, debug_assets, mission, assets)
                        end
                        @check_gl_logs "After 'OpenGL resources' tab"
                    end
                end
            end

            # In 'auto mode', play automatically.
            if auto_mode
                # Print our progress.
                if LOOP.frame_idx > 4000
                    println(stderr, "\tFinishing game...")
                    break
                elseif ((LOOP.frame_idx-1) % 1000) == 0
                    println(stderr, "\tFrame ", LOOP.frame_idx)
                end

                # If not maneuvering, maneuver.
                if !player_is_busy(mission.player.entity)
                    p_dir = grid_dir(mission.player.rot_component.rot)
                    p_voxel = mission.player.pos_component.get_voxel_position()
                    dir_flipR = CabMovementDir(p_dir, 1)
                    dir_flipL = CabMovementDir(p_dir, -1)
                    if can_do_move_from(p_voxel, dir_flipR, MOVE_CLIMB_UP, mission.grid)
                        player_start_moving(mission.player.entity, MOVE_CLIMB_UP, dir_flipR)
                    elseif can_do_move_from(p_voxel, dir_flipR, MOVE_CLIMB_DOWN, mission.grid)
                        player_start_moving(mission.player.entity, MOVE_CLIMB_DOWN, dir_flipR)
                    elseif can_do_move_from(p_voxel, dir_flipR, MOVE_FORWARD, mission.grid)
                        player_start_moving(mission.player.entity, MOVE_FORWARD, dir_flipR)
                    elseif can_drill_from(p_voxel, dir_flipR, v3f(1, 0, 0), mission.grid)
                        player_start_drilling(mission.player, grid_dir(mission.player.rot_component.rot))
                    else
                        # If all else fails, turn in one direction.
                        next_rot = mission.player.rot_component.rot >>
                                     Bplus.fquat(WORLD_UP, deg2rad(30))
                        player_start_turning(mission.player.entity, next_rot)
                    end
                end
            end

            # Give some time to other threads (audio)
            yield()
        end

        TEARDOWN = begin
            if auto_mode
                # During precompilation, Julia is stuck single-threaded,
                #    so let's do audio precompilation now that gameplay is all done.
                if IS_PRECOMPILING
                    println(stderr, "\tPrecompiling the audio engine...")
                    audio_manager.disable_new_sounds = false

                    play_loop(audio_manager, audio_files.ambiance_plain, audio_files.crossfade_seconds_ambiance_plain)
                    play_sound(audio_manager, audio_files.drill)
                    sleep(1) # Not the full duration of the sound
                    play_sound(audio_manager, audio_files.hit_ground)
                    play_sound(audio_manager, audio_files.ambiance_plain, 1.0f0, 3)
                    sleep(10)
                end

                println(stderr, "\tCleaning up")
            end
            @d8_debug begin
                close(debug_gui)
                close(debug_assets)
            end
            close(mission)
            close(assets)
            close(audio_manager)

            if auto_mode
                println(stderr, "Done!")
            end

            0
        end
    end)
end

julia_main()::Cint = inner_main(nothing)

# Precompile the game as much as possible when building this module,
#    by running a session that plays itself automatically.
inner_main(5000)

IS_PRECOMPILING = false

end # module