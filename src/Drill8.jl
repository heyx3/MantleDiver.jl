module Drill8

using Random, Setfield

using CImGui, GLFW, FreeType, ImageIO, FileIO,
      CSyntax, StaticArrays

using Bplus; @using_bplus

# Reconfigure B+'s coordinate system to match Dear ImGUI.
Bplus.BplusCore.Math.get_right_handed() = false
const WORLD_FORWARD = v3f(1, 0, 0)
const WORLD_RIGHT = v3f(0, 1, 0)
const WORLD_UP = v3f(0, 0, 1)

const PI2 = Float32(2π)

# Define @d8_assert and @d8_debug
Bplus.@make_toggleable_asserts d8_


"
Prints the current file and line, along with any data you pass in.
Helps pin down crashes that don't leave a clear stack trace.
"
macro shout(data...)
    return quote
        print(stderr, '\n', $(string(__source__.file)), ":", $(string(__source__.line)))
        if $(!isempty(data))
            print(stderr, " -- ", $(esc.(data)...))
        end
        println(stderr, '\n')
    end
end


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

include("entity_prototypes.jl")
include("level_generators.jl")
include("mission.jl")

include("debug_assets.jl")
include("debug_gui_widgets.jl")


function julia_main()::Cint
    @game_loop begin
        INIT(
            v2i(1280, 770), "Drill8",
            debug_mode = @d8_debug
        )

        SETUP = begin
            mission = Mission(
                PlayerLoadout(
                ),
                v2i(200, 200)
                #, seed = 0x12345
            )
            assets = Assets()

            # In debug mode provide various GUI widgets,
            #    one of which will contain the rendered scene.
            @d8_debug begin
                debug_assets = DebugAssets()
                debug_gui = DebugGui()
            end
        end

        LOOP = begin
            if GLFW.WindowShouldClose(LOOP.context.window)
                break
            end
            # Grab any OpenGL warnings/errors and log them.
            @d8_debug for log in GL.pull_gl_logs()
                log_msg() = sprint(show, log)
                if log.severity in (DebugEventSeverities.high, DebugEventSeverities.medium)
                    @error "OpenGL error: $(log_msg())"
                elseif log.severity == DebugEventSeverities.low
                    @warn "OpenGL warning: $(log_msg())"
                elseif log.severity == DebugEventSeverities.none
                    @info "OpenGL message: $(log_msg())"
                else
                    error("Unhandled case: ", log.severity)
                end
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
            (!continue_mission) && break

            # Draw the game.
            if !@d8_debug
                GL.clear_screen(vRGBAf(1, 0, 1, 0))
                #TODO: Render the world normally.
            else
                screen_size = convert(v2f, GL.get_window_size())
                CImGui.SetNextWindowPos(v2i(0, 0))
                CImGui.SetNextWindowSize(screen_size)
                GUI.gui_window("#MainWnd", C_NULL, CImGui.LibCImGui.ImGuiWindowFlags_NoDecoration) do
                    gui_game_speed(debug_gui, debug_assets)

                    # Draw the tabs.
                    gui_tab_views("#DebugTabs") do

                        gui_tab_item("Game View 2D") do
                            game_view_tab_region = Box2Df(
                                #TODO Handle scroll offset, then move this calculation into a B+ function
                                min = convert(v2f, CImGui.GetCursorPos()) -
                                        convert(v2f, CImGui.GetWindowPos()),
                                size = convert(v2f, CImGui.GetContentRegionAvail())
                            )
                            game_view_area = Box2Df(
                                min=min_inclusive(game_view_tab_region),
                                size=size(game_view_tab_region) * v2f(1, 0.8)
                            )

                            CImGui.Dummy(size(game_view_area)...)
                            gui_debug_game_views(game_view_area, mission, debug_gui)

                            gui_debug_maneuvers(mission, debug_gui)
                        end

                        gui_tab_item("Assets") do
                            gui_visualize_textures(debug_gui, debug_assets, mission, assets)
                        end
                    end
                end
            end
        end

        TEARDOWN = begin
            close(mission)
            close(debug_gui)
            close(debug_assets)
            close(assets)
        end
    end
    return 0
end

end # module