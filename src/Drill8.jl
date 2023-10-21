module Drill8

using Random, Setfield

using CImGui, GLFW, CSyntax

using Bplus
@using_bplus
# Reconfigure B+'s coordinate system to match Dear ImGUI.
Bplus.Math.get_right_handed() = false

const PI2 = Float32(2π)


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

include("ECS/ECS.jl")
using .ECS


@bp_enum(RockTypes::UInt8,
    empty = 0,
    plain = 1,
    gold = 2
)
include("cab.jl")

include("Components/transforms.jl")
include("Components/game_grid.jl")
include("Components/rocks.jl")
include("Components/player.jl")
include("Components/debug_gui_visuals.jl")

include("entity_prototypes.jl")


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

            ecs_world::World = World()
            entity_grid = make_grid(ecs_world)

            # Generate the rock grid.
            rock_grid = fill(RockTypes.plain, 4, 4, 16)
            top_rock_layer::Int = size(rock_grid, 3)
            # Keep the top layer empty.
            rock_grid[:, :, top_rock_layer] .= RockTypes.empty
            # Randomly remove pieces of rock.
            n_subtractions::Int = length(rock_grid) ÷ 5
            for _ in 1:n_subtractions
                local pos::Vec3{<:Integer}
                @do_while begin
                    pos = rand(1:vsize(rock_grid))
                end rock_grid[pos] != RockTypes.plain
                rock_grid[pos] = RockTypes.empty
            end
            # Ensure there's at least one solid rock underneath the top layer,
            #    for the player to spawn on.
            if all(r -> (r==RockTypes.empty), @view rock_grid[:, :, top_rock_layer - 1])
                fill_pos = rand(v3i(1, 1, 2) : vappend(vsize(rock_grid).xy,
                                                       top_rock_layer - 1))
                rock_grid[fill_pos...] = RockTypes.plain
            end
            # Insert some pieces of gold.
            n_golds::Int = 5
            for _ in 1:n_golds
                local pos::Vec3{Int}
                @do_while begin
                    pos = rand(1:vsize(rock_grid))
                end rock_grid[pos] != RockTypes.plain
                rock_grid[pos] = RockTypes.gold
            end

            # Turn the generated grid of data into real entities.
            for grid_pos in 1:vsize(rock_grid)
                if rock_grid[grid_pos] != RockTypes.empty
                    make_rock(ecs_world, grid_pos,
                              rock_grid[grid_pos] == RockTypes.gold)
                end
            end

            # Place the player's cab in the top layer, above solid rock.
            entity_player = make_player(
                ecs_world,
                begin
                    local pos::Vec2{Int}
                    @do_while begin
                        pos = rand(1:get_horz(vsize(rock_grid).xy))
                    end (rock_grid[vappend(pos, top_rock_layer - 1)] == RockTypes.empty)
                end
            )

            # Initialize the GUI for turning and moving.
            TURN_SPEED_DEG_PER_SECOND = 180
            TURN_INCREMENT_DEG = 30

            elapsed_seconds::Float32 = @f32(0)

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
            tick_world(ecs_world, LOOP.delta_seconds)

            # Use GUI widgets to debug render two perpendicular slices of the game.
            size_window_proportionately(Box2Df(min=Vec(0.01, 0.01), max=Vec(0.49, 0.99)))
            gui_window("DebugWorldView", C_NULL, CImGui.ImGuiWindowFlags_NoDecoration) do
                # The UI Y axis corresponds to the world Z axis.
                # The UI X axis will correspond to either the X or Y axis.
                for ui_x_axis in (1, 2)
                    other_x_axis::Int = mod1(ui_x_axis + 1, 2)

                    # Compute data for drawing the rock grid along this slice.
                    sub_wnd_pos = convert(v2i, CImGui.GetWindowPos())
                    sub_wnd_size = convert(v2i, CImGui.GetWindowSize())
                    DRAW_BORDER = 10
                    gui_space = Box2Df(
                        min = sub_wnd_pos + DRAW_BORDER +
                              v2i((sub_wnd_size.x * (ui_x_axis - 1)) ÷ 2,
                                  0),
                        size = (sub_wnd_size - (DRAW_BORDER * 2)) / v2f(2, 1)
                    )
                    world_slice_space = Box2Df(
                        min = let min3D = (one(v3f) - 0.5)
                            Vec(min3D[ui_x_axis], min3D[3])
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

                    # Draw all elements.
                    for (component, entity) in get_components(ecs_world, AbstractDebugGuiVisualsComponent)
                        gui_visualize(component, entity, gui_render_data)
                    end

                    # element_count::v2i = vsize(rock_grid)[ui_x_axis, 3]
                    # draw_size_2d::v2f = convert(v2f, 1 / element_count) *
                    #                     ((sub_wnd_size / v2f(2, 1)) - (DRAW_BORDER * 2) -
                    #                      (DRAW_SPACING * (element_count - 1)))
                    # draw_size = min(draw_size_2d...)
                    # draw_min_pos(cell_2d::v2f) = +(
                    #     sub_wnd_pos, # Low-level drawing is in screen position rather than GUI window position
                    #     v2i((sub_wnd_size.x * (ui_x_axis - 1)) ÷ 2, 0), # Offset based on which slice is being drawn
                    #     DRAW_BORDER, # Padding
                    #     let ipart = map(trunc, cell_2d) # Grid cell offset
                    #         (draw_size + DRAW_SPACING) * (ipart - 1)
                    #     end,
                    #     let fpart = map(f -> f - trunc(f), cell_2d) # Fractional cell offset
                    #         draw_size * fpart
                    #     end
                    # )
                    # sub_wnd_drawing::Ptr = CImGui.GetWindowDrawList()
                    # for element::v2i in 1:element_count
                    #     rock_cell = v3i(i ->
                    #         if i==ui_x_axis
                    #             element.x
                    #         elseif i==other_x_axis
                    #             player_rock_cell[other_x_axis]
                    #         elseif i==3
                    #             element_count.y - element.y + 1
                    #         else
                    #             error("Unexpected axis ", i,
                    #                     "UIx:", ui_x_axis,
                    #                     "  other: ", other_x_axis)
                    #         end
                    #     )

                    #     draw_min = draw_min_pos(convert(v2f, element))
                    #     draw_max = draw_min + draw_size

                    #     # Generate a unique ID for each iteration of this loop,
                    #     #    otherwise Dear ImGUI will conflate all these widgets.
                    #     gui_with_nested_id(element.x + (element.y * element_count.x)) do
                    #         if rock_grid[rock_cell] == RockTypes.plain
                    #             CImGui.ImDrawList_AddRectFilled(sub_wnd_drawing,
                    #                                             draw_min, draw_max,
                    #                                             CImGui.ImVec4(0.4, 0.15, 0.01, 1),
                    #                                             @f32(0), CImGui.LibCImGui.ImDrawFlags_None)
                    #         elseif rock_grid[rock_cell] == RockTypes.gold
                    #             CImGui.ImDrawList_AddRectFilled(sub_wnd_drawing,
                    #                                             draw_min, draw_max, #0xE5aa06ff
                    #                                             CImGui.ImVec4(0.93, 0.66, 0.05, 1),
                    #                                             @f32(0), CImGui.ImDrawFlags_None)
                    #         elseif rock_grid[rock_cell] == RockTypes.empty
                    #             # Draw nothing
                    #         else
                    #             error("Unhandled case: ", rock_grid[rock_cell])
                    #         end
                    #     end
                    # end

                    # # Display the player among the rocks.
                    # player_ui_grid_pos = v2f(cab_view.pos[ui_x_axis],
                    #                          element_count.y - cab_view.pos[3] + 1)
                    # player_draw_pos = draw_min_pos(player_ui_grid_pos + @f32(0.5))
                    # CImGui.ImDrawList_AddCircle(sub_wnd_drawing,
                    #                             player_draw_pos, 10,
                    #                             CImGui.ImVec4(0.2, 1, 0.5, 1),
                    #                             0, 3)
                    # player_ui_forward = v2f(cab_view.forward[ui_x_axis], cab_view.forward[3])
                    # scaled_forward = @f32(15) *
                    #                  map(sign, player_ui_forward) *
                    #                  (abs(player_ui_forward) ^ @f32(2))
                    # CImGui.ImDrawList_AddLine(sub_wnd_drawing,
                    #                           player_draw_pos,
                    #                           player_draw_pos + scaled_forward,
                    #                           CImGui.ImVec4(1, 0.7, 0.7, 1),
                    #                           3)
                end
            end

            # Provide some turn and movement controls.
            size_window_proportionately(Box2Df(min=Vec(0.51, 0.01), max=Vec(0.99, 0.99)))
            gui_with_padding(CImGui.ImVec2(20, 20)) do
            gui_window("TurnAndMovement", C_NULL, CImGui.ImGuiWindowFlags_NoDecoration) do
                # Disable certain buttons under certain conditions.
                function panel_button(button_args...;
                                      disable_when_turning::Bool = false,
                                      disable_when_moving::Bool = false,
                                      force_disable::Bool = false)::Bool
                    disable_button = force_disable ||
                                     (disable_when_turning && (vdot(turning_target, cab.facing_dir) > 0.01)) ||
                                     (disable_when_moving && exists(cab.current_action))

                    disable_button && CImGui.PushStyleColor(CImGui.ImGuiCol_Button,
                                                             CImGui.ImVec4(0.65, 0.4, 0.4, 1))
                    result::Bool = CImGui.Button(button_args...)
                    disable_button && CImGui.PopStyleColor()

                    return result && !disable_button
                end

                # Provide 'turn' buttons.
                gui_within_group() do
                    BUTTON_SIZE = (50, 25)
                    if panel_button("<--", BUTTON_SIZE)
                        turning_target = q_apply(fquat(v3f(0, 0, 1), -deg2rad(TURN_INCREMENT_DEG)),
                                                 turning_target)
                    end
                    CImGui.SameLine()
                    CImGui.Dummy(BUTTON_SIZE[1] * 1.0, 1)
                    CImGui.SameLine()
                    if panel_button("-->", BUTTON_SIZE)
                        turning_target = q_apply(fquat(v3f(0, 0, 1), deg2rad(TURN_INCREMENT_DEG)),
                                                 turning_target)
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
                next_move_flip_ui = convert(Cint, inv_lerp_i(-1, 1, next_move_dir.flip))
                @c CImGui.SliderInt("Side", &next_move_flip_ui,
                                    0, 1,
                                    "",
                                    CImGui.ImGuiSliderFlags_None)
                @set! next_move_dir.flip = Int8(inv_lerp_i(-1, +1, next_move_flip_ui))

                # Provide buttons for all movements with the given 'flip' direction.
                (MOVE_FORWARD, MOVE_CLIMB, MOVE_DROP) = LEGAL_MOVES
                (forward_is_legal, climb_is_legal, drop_is_legal) =
                    is_legal.(LEGAL_MOVES, Ref(next_move_dir),
                              Ref(player_rock_cell), Ref(rock_grid))
                if panel_button("x##Move"; disable_when_moving=true, force_disable=!forward_is_legal)
                    cab.current_action = CabMovementState(MOVE_FORWARD, next_move_dir)
                end
                CImGui.SameLine()
                CImGui.Dummy(10, 0)
                CImGui.SameLine()
                if panel_button("^^##Move"; disable_when_moving=true, force_disable=!climb_is_legal)
                    cab.current_action = CabMovementState(MOVE_CLIMB, next_move_dir)
                end
                CImGui.SameLine()
                CImGui.Dummy(10, 0)
                CImGui.SameLine()
                if panel_button("V##Move"; disable_when_moving=true, force_disable=!drop_is_legal)
                    cab.current_action = CabMovementState(MOVE_DROP, next_move_dir)
                end

                CImGui.Dummy(0, 50)

                # Provide buttons for drilling.
                function is_drill_legal(canonical_dir::Vec3)
                    drilled_pos = cab_view.pos + convert(v3f, rotate_cab_movement(canonical_dir, next_move_dir))
                    drilled_grid_pos = rock_grid_idx(drilled_pos)
                    return is_touching(Box3Di(min=one(v3i), size=vsize(rock_grid)), drilled_grid_pos) &&
                           (rock_grid[drilled_grid_pos] != RockTypes.empty)
                end
                CImGui.Text("DRILL"); CImGui.SameLine()
                CImGui.Dummy(10, 0); CImGui.SameLine()
                if panel_button("*##Drill"; disable_when_moving=true,
                                     force_disable=!is_drill_legal(v3f(1, 0, 0)))
                #begin
                    cab.current_action = CabDrillState(DrillDirection(next_move_dir.axis,
                                                                      next_move_dir.dir),
                                                       elapsed_seconds)
                end
                CImGui.SameLine()
                if panel_button("V##Drill"; disable_when_moving=true,
                                      force_disable=!is_drill_legal(v3f(0, 0, -1)))
                #begin
                    cab.current_action = CabDrillState(DrillDirection(3, -1), elapsed_seconds)
                end
                CImGui.SameLine()
                if panel_button(">>##Drill6"; disable_when_moving=true,
                                      force_disable=!is_drill_legal(v3f(0, 1, 0)))
                #begin
                    cab.current_action = CabDrillState(DrillDirection(mod1(next_move_dir.axis + 1, 2),
                                                                      next_move_dir.dir * next_move_dir.flip),
                                                       elapsed_seconds)
                end
            end end # Window and padding
        end
    end
    return 0
end

end # module