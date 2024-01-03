module Drill8

using Random, Setfield

using CImGui, GLFW, CSyntax,
      StaticArrays

using Bplus
@using_bplus
# Reconfigure B+'s coordinate system to match Dear ImGUI.
Bplus.BplusCore.Math.get_right_handed() = false

const PI2 = Float32(2π)

@make_toggleable_asserts d8_


"
Prints the current file and line, along with any data you pass in.
Intended to help pin down crashes that don't leave a clear stack trace.
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


# The world grid coordinate system places cell centers at integer values.
grid_idx(world_pos::Vec3)::v3i = round(Int32, world_pos)
is_min_half_of_grid_cell(f::Real) = (f > convert(typeof(f), 0.5))
is_min_half_of_grid_cell(p::Vec) = map(is_min_half_of_grid_cell, v)

include("grid_directions.jl")
include("cab.jl")

include("Components/transforms.jl")
include("Components/game_grid.jl")
include("Components/rocks.jl")
include("Components/player_maneuvers.jl")
include("Components/debug_gui_visuals.jl")

include("entity_prototypes.jl")
include("level_generators.jl")
include("mission.jl")

include("Hud/windows.jl")



function julia_main()::Cint
    @game_loop begin
        INIT(
            v2i(1280, 720), "Drill8"
        )

        SETUP = begin
            mission = Mission(
                PlayerLoadout(
                )
                #, seed = 0x12345
            )

            window_debug_view_x = create_window_debug_view(mission, 1)
            window_debug_view_y = create_window_debug_view(mission, 2)
            window_maneuvers = create_window_maneuvers(mission)
            ALL_WINDOWS = [ window_debug_view_x, window_debug_view_y, window_maneuvers ]

            # Size each HUD window in terms of the overall window size.
            function size_window_proportionately(uv_space::Box2Df)
                local window_size::v2i = get_window_size(LOOP.context)
                local pos::v2f = window_size * min_inclusive(uv_space)
                w_size = window_size * size(uv_space)
                CImGui.SetNextWindowPos(CImGui.ImVec2(pos...))
                CImGui.SetNextWindowSize(CImGui.ImVec2(w_size...))
            end
        end

        LOOP = begin
            if GLFW.WindowShouldClose(LOOP.context.window)
                break
            end

            # Update game logic.
            if !tick!(mission, LOOP.delta_seconds)
                break
            end

            # Draw the hud.
            size_window_proportionately(Box2Df(min=Vec(0.01, 0.01), max=Vec(0.245, 0.99)))
                tick!(window_debug_view_x)
            size_window_proportionately(Box2Df(min=Vec(0.255, 0.01), max=Vec(0.49, 0.99)))
                tick!(window_debug_view_y)
            size_window_proportionately(Box2Df(min=Vec(0.51, 0.01), max=Vec(0.99, 0.99)))
                gui_with_padding(() -> tick!(window_maneuvers), CImGui.ImVec2(20, 20))
        end

        TEARDOWN = begin
            close.(ALL_WINDOWS)
        end
    end
    return 0
end

end # module