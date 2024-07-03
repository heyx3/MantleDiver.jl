module Drill8

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
include("Renderer/framebuffer.jl")
include("Renderer/assets.jl")
include("Renderer/world_viewport.jl")

include("Components/Core/transforms.jl")
include("Components/Core/grid_data.jl")
include("Components/Core/grid_event_responders.jl")
include("Components/Core/grid_element_bulk.jl")
include("Components/Core/grid_manager.jl")
include("Components/Core/grid_element.jl")
include("Components/Core/debug_gui_visuals.jl")
include("Components/Core/renderable.jl")
include("Components/GridObjects/rock.jl")
include("Components/PlayerCab/data.jl")
include("Components/PlayerCab/maneuvers.jl")
include("Components/PlayerCab/rendering.jl")

include("Game/entity_prototypes.jl")
include("Game/level_generators.jl")
include("Game/mission.jl")
include("Game/input.jl")

include("Debug/debug_assets.jl")
include("Debug/debug_gui_widgets.jl")


get_imgui_current_drawable_region() = Box2Df(
    #TODO Handle scroll offset, then move this calculation into a B+ function
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
            # Check the path we're running from.
            if !isdir(ASSETS_FOLDER)
                error("Running from a location with no 'assets' folder! ",
                        "This is not the right place to run from. ",
                        pwd())
            end

            mission = Mission(
                PlayerLoadout(
                ),
                v2i(50, 50)
            )
            @d8_debug(@check_gl_logs "After mission creation")
            register_mission_inputs()

            assets = Assets()
            @d8_debug(@check_gl_logs "After asset creation")

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
            player_viewport_settings = ViewportDrawSettings(
                output_mode = @d8_debug(debug_gui.render_mode, FramebufferRenderMode.regular)
            )
            render_mission(mission, assets, player_viewport_settings)
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

                        gui_tab_item("Game View 2D") do
                            is_in_main_view = false

                            game_view_tab_region = get_imgui_current_drawable_region()
                            game_view_area = Box2Df(
                                min=min_inclusive(game_view_tab_region),
                                size=size(game_view_tab_region) * v2f(1, 0.8)
                            )

                            CImGui.Dummy(size(game_view_area)...)
                            gui_debug_game_views(game_view_area, mission, debug_gui)

                            gui_debug_maneuvers(mission, debug_gui)
                        end
                        @check_gl_logs "After 'Game View 2D' tab"

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
                if !player_is_busy(mission.player)
                    p_dir = grid_dir(mission.player_rot.rot)
                    p_voxel = mission.player_pos.get_voxel_position()
                    dir_flipR = CabMovementDir(p_dir, 1)
                    dir_flipL = CabMovementDir(p_dir, -1)
                    if can_do_move_from(p_voxel, dir_flipR, LEGAL_MOVES[2], mission.grid)
                        player_start_moving(mission.player, LEGAL_MOVES[2], dir_flipR)
                    elseif can_do_move_from(p_voxel, dir_flipR, LEGAL_MOVES[3], mission.grid)
                        player_start_moving(mission.player, LEGAL_MOVES[3], dir_flipR)
                    elseif can_do_move_from(p_voxel, dir_flipR, LEGAL_MOVES[1], mission.grid)
                        player_start_moving(mission.player, LEGAL_MOVES[1], dir_flipR)
                    elseif can_drill_from(p_voxel, dir_flipR, v3f(1, 0, 0), mission.grid)
                        player_start_drilling(mission.player, grid_dir(mission.player_rot.rot))
                    else
                        # If all else fails, turn in one direction.
                        next_rot = get_orientation(mission.player) >>
                                     Bplus.fquat(WORLD_UP, deg2rad(30))
                        player_start_turning(mission.player, next_rot)
                    end
                end
            end
        end

        TEARDOWN = begin
            if auto_mode
                println(stderr, "\tCleaning up")
            end
            @d8_debug begin
                close(debug_gui)
                close(debug_assets)
            end
            close(mission)
            close(assets)

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

end # module