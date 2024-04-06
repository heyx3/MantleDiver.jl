module Drill8

using Random, Setfield

using CImGui, GLFW, FreeType, ImageIO, FileIO,
      CSyntax, StaticArrays

using Bplus; @using_bplus

# Reconfigure B+'s coordinate system to match Dear ImGUI.
Bplus.BplusCore.Math.get_right_handed() = false

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
include("Components/Core/grid_manager.jl")
include("Components/Core/grid_element.jl")
include("Components/Core/debug_gui_visuals.jl")

include("Components/GridObjects/rock.jl")

include("Components/PlayerCab/data.jl")
include("Components/PlayerCab/maneuvers.jl")
include("Components/PlayerCab/rendering.jl")

include("entity_prototypes.jl")
include("level_generators.jl")
include("mission.jl")

include("debug_assets.jl")
include("debug_gui_widgets.jl")

@bp_enum(DebugGuiTab,
    game,
    assets
)
@bp_enum(DebugGuiSpeed,
    play,
    pause,
    fast_forward
)


function julia_main()::Cint
    @game_loop begin
        INIT(
            v2i(1280, 770), "Drill8"
        )

        SETUP = begin
            mission = Mission(
                PlayerLoadout(
                )
                #, seed = 0x12345
            )
            assets = Assets()

            # In debug mode provide various GUI widgets,
            #    one of which will contain the rendered scene.
            @d8_debug begin
                debug_assets = DebugAssets()
                debug_gui = DebugGui()
                current_tab::E_DebugGuiTab = DebugGuiTab.game
                current_speed::E_DebugGuiSpeed = DebugGuiSpeed.play
                fast_forward_speed::Int = 2
                min_asset_tex_length::Float32 = 128
            end
        end

        LOOP = begin
            if GLFW.WindowShouldClose(LOOP.context.window)
                break
            end

            # Tick the mission, and quit if it ends.
            continue_mission::Bool = if @d8_debug
                if current_speed == DebugGuiSpeed.play
                    tick!(mission, LOOP.delta_seconds)
                elseif current_speed == DebugGuiSpeed.pause
                    true
                elseif current_speed == DebugGuiSpeed.fast_forward
                    b = true
                    for i in 1:fast_forward_speed
                        b |= tick!(mission, LOOP.delta_seconds)
                        (!b) && break
                    end
                    b
                else
                    error("Unhandled case: ", current_speed)
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
                    gui_with_nested_id("SpeedControls") do
                        for speed::E_DebugGuiSpeed in DebugGuiSpeed.instances()
                            tex::Texture = if speed == DebugGuiSpeed.play
                                debug_assets.tex_button_play
                            elseif speed == DebugGuiSpeed.pause
                                debug_assets.tex_button_pause
                            elseif speed == DebugGuiSpeed.fast_forward
                                debug_assets.tex_button_fast_forward
                            else
                                error("Unhandled: ", speed)
                            end
                            tint = if speed == current_speed
                                v4f(1, 1, 1, 1)
                            else
                                v4f(0.5, 0.5, 0.5, 1)
                            end
                            GUI.gui_with_nested_id(Int(speed)) do
                                if CImGui.ImageButton(gui_tex_handle(tex),
                                                      v2f(30, 30),
                                                      (0, 0), (1, 1),
                                                      -1, (0, 0, 0, 0),
                                                      tint.data)
                                    current_speed = speed
                                end
                            end
                            CImGui.SameLine()
                        end
                        # Undo the last SameLine()
                        CImGui.Dummy(0.0001, 0.0001)
                    end

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
                            @c CImGui.SliderFloat(
                                "Min Size", &min_asset_tex_length,
                                1, 1024
                            )

                            function show_tex(name::String, tex::GL.Texture)
                                view = GL.get_view(tex, GL.TexSampler{2}(
                                    pixel_filter=GL.PixelFilters.rough
                                ))
                                handle = GUI.gui_tex_handle(view)
                                size::v2u = GL.tex_size(tex)

                                # If the texture is very small, blow it up.
                                scale_up_ratio = min_asset_tex_length / min(size)
                                draw_size::v2f = if scale_up_ratio > 1
                                    size * scale_up_ratio
                                else
                                    size
                                end

                                CImGui.Text(name * " ($(size.x)x$(size.y))")
                                CImGui.Image(handle, draw_size)
                                CImGui.Spacing()
                            end
                            show_tex("Char Atlas", assets.chars_atlas)
                            show_tex("Char UV Lookup", assets.chars_atlas_lookup)
                            show_tex("Palette", assets.palette)
                        end
                    end
                end
            end
        end

        TEARDOWN = begin
            close(debug_assets)
            close(assets)
        end
    end
    return 0
end

end # module