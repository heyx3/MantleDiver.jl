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
include("level_generator.jl")


function julia_main()::Cint
    @game_loop begin
        INIT(
            v2i(1280, 720), "Drill8"
        )

        SETUP = begin
            # Randomize the game each time, but print the random seed used.
            # That way we can debug weird things that happen.
            game_seed = rand(UInt)
            println("Seed used: ", game_seed)
            Random.seed!(game_seed)

            player_start_pos = v3i(0, 0, 16)

            # Set up the ECS world.
            ecs_world::World = World()
            entity_grid = make_grid(ecs_world, vsize(rock_grid),
                                    MainGenerator, player_start_pos,
                                      5, 0.1,
                                      0.8, 2.4)
            component_grid = get_component(entity_grid, GridManager)

            # Spawn the player.
            entity_player = make_player(ecs_world, player_start_pos)
            check_for_fall(entity_player, component_grid)

            # Initialize the GUI for turning and moving.
            TURN_INCREMENT_DEG = @f32(30)
            next_move_flip::Int8 = 1
            elapsed_seconds::Float32 = @f32(0)

            # Initialize the GUI debug world display.
            sorted_gui_display_elements = Vector{Tuple{DebugGuiVisuals, Entity, Int64}}()

            # Size each sub-window in terms of the overall window size.
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
            elapsed_seconds += LOOP.delta_seconds
            ECS.tick_world(ecs_world, LOOP.delta_seconds)

            # Use GUI widgets to debug render two perpendicular slices of the game.
            size_window_proportionately(Box2Df(min=Vec(0.01, 0.01), max=Vec(0.49, 0.99)))
            gui_window("DebugWorldView", C_NULL, CImGui.ImGuiWindowFlags_NoDecoration) do
                # Presort drawn elements by their priority.
                empty!(sorted_gui_display_elements)
                for (component, entity) in get_components(ecs_world, DebugGuiVisuals)
                    push!(sorted_gui_display_elements,
                          (component, entity, component.draw_order()))
                end
                sort!(sorted_gui_display_elements, by=(data->data[3]))

                sub_wnd_pos = convert(v2i, CImGui.GetWindowPos())
                sub_wnd_size = convert(v2i, CImGui.GetWindowSize())
                sub_wnd_space = Box2Df(
                    min=sub_wnd_pos,
                    size=sub_wnd_size
                )
                DRAW_BORDER = 10

                # The UI Y axis corresponds to the world Z axis.
                # The UI X axis will correspond to either the X or Y axis.
                for ui_x_axis in (1, 2)
                    other_x_axis::Int = mod1(ui_x_axis + 1, 2)

                    # Compute data for drawing the rock grid along this slice.
                    gui_space = Box2Df(
                        min = min_inclusive(sub_wnd_space) + DRAW_BORDER +
                              if ui_x_axis == 1
                                  v2f(0, 0)
                              else
                                  v2f(center(sub_wnd_space).x + DRAW_BORDER, 0)
                              end,
                        max = if ui_x_axis == 1
                                  v2f(center(sub_wnd_space).x,
                                      max_inclusive(sub_wnd_space).y)
                              else
                                  max_inclusive(sub_wnd_space)
                              end - DRAW_BORDER
                    )
                    world_slice_space = Box2Df(
                        min = let min3D = one(v3f)
                            Vec(min3D[ui_x_axis], min3D[3]) - 0.5
                        end,
                        size = let size3D = vsize(rock_grid)
                            Vec(size3D[ui_x_axis], size3D[3])
                        end
                    )
                    gui_render_data = DebugGuiRenderData(
                        ui_x_axis,
                        get_voxel_position(entity_player)[other_x_axis],
                        gui_space, world_slice_space,
                        CImGui.GetWindowDrawList()
                    )

                    # Draw the background.
                    CImGui.ImDrawList_AddRectFilled(
                        CImGui.GetWindowDrawList(),
                        min_inclusive(gui_space),
                        max_inclusive(gui_space),
                        CImGui.ImVec4(0.7, 0.7, 0.7, 0.7),
                        @f32(4),
                        CImGui.LibCImGui.ImDrawFlags_None
                    )

                    # Draw all elements.
                    for (component, entity, _) in sorted_gui_display_elements
                        component.visualize(gui_render_data)
                    end
                end

                CImGui.ImDrawList_AddLine(
                    CImGui.GetWindowDrawList(),
                    CImGui.ImVec2(
                        sub_wnd_pos.x + (DRAW_BORDER * 2) + (sub_wnd_size.x ÷ 2),
                        sub_wnd_pos.y + DRAW_BORDER
                    ),
                    CImGui.ImVec2(
                        sub_wnd_pos.x + (DRAW_BORDER * 2) + (sub_wnd_size.x ÷ 2),
                        sub_wnd_pos.y + sub_wnd_size.y - DRAW_BORDER
                    ),
                    CImGui.ImVec4(0.9, 0.9, 0.9, 1.0),
                    3
                )
            end

            # Provide some turn and movement controls.
            size_window_proportionately(Box2Df(min=Vec(0.51, 0.01), max=Vec(0.99, 0.99)))
            gui_with_padding(CImGui.ImVec2(20, 20)) do
            gui_window("TurnAndMovement", C_NULL, CImGui.ImGuiWindowFlags_NoDecoration) do
                function maneuver_button(button_args...; force_disable::Bool = false)::Bool
                    disable_button = force_disable || player_is_busy(entity_player)

                    disable_button && CImGui.PushStyleColor(CImGui.ImGuiCol_Button,
                                                             CImGui.ImVec4(0.65, 0.4, 0.4, 1))
                    result::Bool = CImGui.Button(button_args...)
                    disable_button && CImGui.PopStyleColor()

                    return result && !disable_button
                end

                # Provide 'turn' buttons.
                gui_within_group() do
                    BUTTON_SIZE = (50, 25)
                    if maneuver_button("<--", BUTTON_SIZE)
                        turn = fquat(get_up_vector(), -deg2rad(TURN_INCREMENT_DEG))
                        new_orientation = get_orientation(entity_player) >> turn
                        player_start_turning(entity_player, new_orientation)
                    end
                    CImGui.SameLine()
                    CImGui.Dummy(BUTTON_SIZE[1] * 1.0, 1)
                    CImGui.SameLine()
                    if maneuver_button("-->", BUTTON_SIZE)
                        turn = fquat(get_up_vector(), deg2rad(TURN_INCREMENT_DEG))
                        new_orientation = get_orientation(entity_player) >> turn
                        player_start_turning(entity_player, new_orientation)
                    end
                end
                # Draw a box around the 'turn' buttons' interface.
                CImGui.ImDrawList_AddRect(CImGui.GetWindowDrawList(),
                                          convert(v2f, CImGui.GetItemRectMin()) - 5,
                                          convert(v2f, CImGui.GetItemRectMax()) + 5,
                                          CImGui.ImVec4(0.6, 0.6, 0.9, 1),
                                          10, CImGui.LibCImGui.ImDrawFlags_RoundCornersAll,
                                          3)

                # Edit the 'flip' direction with a little slider.
                next_move_flip_ui = convert(Cint, inv_lerp_i(-1, +1, next_move_flip))
                @c CImGui.SliderInt("Side", &next_move_flip_ui,
                                    0, 1,
                                    "",
                                    CImGui.ImGuiSliderFlags_None)
                @set! next_move_flip = convert(Int8, lerp(-1, +1, next_move_flip_ui))

                # Provide buttons for all movements, with the current 'flip' direction.
                current_grid_direction = grid_dir(get_orientation(entity_player))
                current_move_dir = CabMovementDir(current_grid_direction, next_move_flip)
                (MOVE_FORWARD, MOVE_CLIMB, MOVE_DROP) = LEGAL_MOVES
                (forward_is_legal, climb_is_legal, drop_is_legal) =
                    is_legal.(LEGAL_MOVES, Ref(current_move_dir),
                              Ref(get_voxel_position(entity_player)), Ref(is_grid_free))
                if maneuver_button("x##Move"; force_disable=!forward_is_legal)
                    player_start_moving(entity_player, MOVE_FORWARD, current_move_dir)
                end
                CImGui.SameLine()
                CImGui.Dummy(10, 0)
                CImGui.SameLine()
                if maneuver_button("^^##Move"; force_disable=!climb_is_legal)
                    player_start_moving(entity_player, MOVE_CLIMB, current_move_dir)
                end
                CImGui.SameLine()
                CImGui.Dummy(10, 0)
                CImGui.SameLine()
                if maneuver_button("V##Move"; force_disable=!drop_is_legal)
                    player_start_moving(entity_player, MOVE_DROP, current_move_dir)
                end

                CImGui.Dummy(0, 50)

                # Provide buttons for drilling.
                function is_drill_legal(canonical_dir::Vec3)
                    world_dir::v3f = rotate_cab_movement(convert(v3f, canonical_dir),
                                                         current_move_dir)
                    drilled_pos = get_precise_position(entity_player) + world_dir
                    drilled_grid_pos = grid_idx(drilled_pos)
                    return is_touching(Box3Di(min=one(v3i), size=vsize(rock_grid)), drilled_grid_pos) &&
                           !is_grid_free(drilled_grid_pos)
                end
                CImGui.Text("DRILL"); CImGui.SameLine()
                CImGui.Dummy(10, 0); CImGui.SameLine()
                if maneuver_button("*##Drill"; force_disable=!is_drill_legal(v3f(1, 0, 0)))
                #begin
                    player_start_drilling(entity_player, current_grid_direction)
                end
                CImGui.SameLine()
                if maneuver_button("V##Drill"; force_disable=!is_drill_legal(v3f(0, 0, -1)))
                #begin
                    player_start_drilling(entity_player, grid_dir(-get_up_vector()))
                end
                CImGui.SameLine()
                if maneuver_button(">>##Drill6"; force_disable=!is_drill_legal(v3i(0, 1, 0)))
                #begin
                    drill_dir = grid_dir(rotate_cab_movement(v3i(0, 1, 0), current_move_dir))
                    player_start_drilling(entity_player, drill_dir)
                end
            end end # Window and padding
        end
    end
    return 0
end

end # module