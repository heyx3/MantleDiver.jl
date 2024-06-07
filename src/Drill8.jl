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
include("Renderer/framebuffer.jl")
include("Renderer/chars.jl")
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

function julia_main()::Cint
    Bplus.@game_loop begin
        INIT(
            v2i(1280, 770), "Drill8",
            debug_mode = @d8_debug
        )

        SETUP = begin
            mission = Mission(
                PlayerLoadout(
                ),
                v2i(50, 50)
                #, seed = 0x12345
            )
            @d8_debug(@check_gl_logs "After mission creation")
            register_mission_inputs()

            assets = Assets()
            @d8_debug(@check_gl_logs "After asset creation")

            # In debug mode provide various GUI widgets,
            #    one of which will contain the rendered scene.
            @d8_debug begin
                debug_assets = DebugAssets()
                @check_gl_logs "After DebugAssets creation"
                debug_gui = DebugGui()
                @check_gl_logs "After DebugGui creation"
                debug_game_render = GL.Target(
                    convert(v2u, mission.player_viewport.resolution * 14),
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

            GLFW.ShowWindow(LOOP.context.window)
        end

        LOOP = begin
            @d8_debug(@check_gl_logs "Start of iteration " LOOP.frame_idx)
            if GLFW.WindowShouldClose(LOOP.context.window)
                break
            end

            # Tick the mission, and quit if it ends.
            continue_mission::Bool = if @d8_debug
                if debug_gui.gameplay_speed == DebugGuiSpeed.play
                    tick!(mission, LOOP.delta_seconds)
                elseif debug_gui.gameplay_speed == DebugGuiSpeed.pause
                    true
                elseif debug_gui.gameplay_speed == DebugGuiSpeed.fast_forward
                    b = true
                    for i in 1:debug_gui.fast_forward_speed
                        b |= tick!(mission, LOOP.delta_seconds)
                        (!b) && break
                    end
                    b
                else
                    error("Unhandled case: ", debug_gui.gameplay_speed)
                end
            else
                tick!(mission, LOOP.delta_seconds)
            end
            @d8_debug(@check_gl_logs "After mission tick")
            (!continue_mission) && break

            # Handle mission inputs.
            if @d8_debug is_in_main_view true
                update_mission_inputs(mission)
            end

            # Render the player's POV.
            player_viewport_settings = ViewportDrawSettings(

            )
            render_mission(mission, assets, player_viewport_settings)
            @d8_debug(@check_gl_logs "After mission render")

            # Draw the game to the screen (or in debug, to a Target).
            @d8_debug target_activate(debug_game_render)
            GL.clear_screen(vRGBAf(1, 0, 1, 0))
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

                            draw_list = CImGui.GetForegroundDrawList()
                            game_view_tab_region = get_imgui_current_drawable_region()

                            # Draw an XYZ axis indicator as Dear ImGUI lines.
                            BASIS_SCREEN_LENGTH = @f32(50)
                            player_rot_basis::Bplus.Math.VBasis = q_basis(mission.player_rot.rot)
                            # Pitch the view down a little bit since the player's view is always orthogonal
                            #    and this removes any depth clues in the axis render.
                            player_rot_basis = Bplus.vbasis(vnorm(player_rot_basis.forward + v3f(0, 0, -0.2)),
                                                            player_rot_basis.up)
                            basis_camera = Bplus.BplusTools.Cam3D{Float32}(
                                forward=player_rot_basis.forward,
                                up=player_rot_basis.up,
                                projection = OrthographicProjection{Float32}(
                                    min=v3f(-1, -1, -1),
                                    max=v3f(1, 1, 1)
                                )
                            )
                            basis_vec_to_screen::fmat4x4 = m_combine(
                                cam_view_mat(basis_camera),
                                cam_projection_mat(basis_camera)
                            )
                            basis_screen_origin = v2f(
                                min_inclusive(game_view_tab_region).x +
                                   debug_game_render.size.x +
                                   BASIS_SCREEN_LENGTH + 10,
                                center(game_view_tab_region).y
                            )
                            HALF_LINE_THICKNESS = 2.5f0
                            for axis in 1:3
                                world_axis = zero(v3f)
                                @set! world_axis[axis] = 1

                                gui_axis_3d::v3f = vnorm(Bplus.m_apply_vector_affine(basis_vec_to_screen, world_axis))
                                gui_axis::v2f = gui_axis_3d.xy
                                @set! gui_axis.y = -gui_axis.y # Flip for Dear ImGUI coordinates

                                color = (
                                    # Note that colors are ABGR
                                    0xff0000ff,
                                    0xff00ff00,
                                    0xffff0000
                                )[axis]

                                CImGui.AddLine(
                                    draw_list,
                                    basis_screen_origin,
                                    basis_screen_origin + (BASIS_SCREEN_LENGTH * gui_axis),
                                    color,
                                    lerp(3.0, 4.5, -gui_axis_3d.z) # The Z ranges from -1 to 1
                                )
                            end

                            CImGui.Image(GUI.gui_tex_handle(debug_game_render.attachment_colors[1].tex),
                                         convert(v2f, debug_game_render.size),
                                         # Flip UV y:
                                         (0,1), (1,0))

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
                    end
                end
            end
        end

        TEARDOWN = begin
            @d8_debug begin
                close(debug_gui)
                close(debug_assets)
            end
            close(mission)
            close(assets)
        end
    end
    return 0
end

end # module