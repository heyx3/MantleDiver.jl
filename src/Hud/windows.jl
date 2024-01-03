"A Dear ImGUI window that displays during missions"
Base.@kwdef mutable struct WindowController{TUpdate<:Base.Callable}
    mission::Mission

    # Pixel-space window bounds.
    # Automatically updated every tick.
    screen_area::Box2Df = Box2Df()

    window_label::String
    window_flags::CImGui.ImGuiWindowFlags_ = CImGui.ImGuiWindowFlags_NoDecoration

    update::TUpdate # (this, extra_args...; kw_args...) -> Any
    shutdown::Base.Callable = (wnd::WindowController) -> nothing
end
WindowController(mission, label, callback; kw...) = WindowController{typeof(callback)}(;
    mission=mission,
    window_label=label,
    update=callback,
    kw...
)

"Updates the window and returns the output of its update callback"
function tick!(wnd::WindowController, extra_args...; kw_args...)
    gui_window(wnd.window_label, C_NULL, wnd.window_flags) do
        wnd.screen_area = Box2Df(
            min=convert(v2f, CImGui.GetWindowPos()),
            size=convert(v2f, CImGui.GetWindowSize())
        )
        wnd.update(wnd, extra_args...; kw_args...)
    end
end

Base.close(wnd::WindowController) = wnd.shutdown(wnd)



"Creates a window that visualizes the player's current X or Y slice of the world"
function create_window_debug_view(mission::Mission, horizontal_axis::Int;
                                  label_extra::String = "")
    if !in(horizontal_axis, (1, 2))
        error("horizontal_axis param must be 1 or 2, got: ", horizontal_axis)
    end

    # Window state variables:
    display_elements = Vector{Tuple{DebugGuiVisuals, Entity, Int64}}()
    other_x_axis::Int = mod1(horizontal_axis + 1, 2)

    # Window logic:
    window_logic = (wnd::WindowController) -> begin
        # Presort drawn elements by their priority.
        empty!(display_elements)
        for (component, entity) in get_components(wnd.mission.ecs, DebugGuiVisuals)
            push!(display_elements,
                (component, entity, component.draw_order()))
        end
        sort!(display_elements, by=(data->data[3]))

        DRAW_BORDER = 10

        # The UI Y axis corresponds to the world Z axis.
        # The UI X axis will correspond to either the X or Y axis.

        # Compute data for drawing the world grid along this slice.
        gui_space = Box2Df(
            min = min_inclusive(wnd.screen_area) + DRAW_BORDER,
            max = max_inclusive(wnd.screen_area) - DRAW_BORDER
        )
        world_slice_space = Box2Df(
            center = let center3D = wnd.mission.player_pos.get_precise_position()
                Vec(center3D[horizontal_axis], center3D[3])
            end,
            size = let size3D = v3i(4, 4, 10)
                Vec(size3D[horizontal_axis], size3D[3])
            end
        )
        gui_render_data = DebugGuiRenderData(
            horizontal_axis,
            wnd.mission.player_pos.get_voxel_position()[other_x_axis],
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
        gui_with_clip_rect(gui_render_data.gui_range, false, gui_render_data.draw_list) do
            for (component, entity, _) in display_elements
                component.visualize(gui_render_data)
            end
        end
    end

    return WindowController(
        mission,
        "DebugWorldView $(('X', 'Y')[horizontal_axis])$label_extra",
        window_logic
    )
end

"Creates a window for doing player maneuvers (turning, moving, drilling)"
function create_window_maneuvers(mission::Mission; label_extra::String = "")
    # Window state variables:
    TURN_INCREMENT_DEG = @f32(30)
    next_move_flip::Int8 = 1

    # Window state logic:
    window_logic = (wnd::WindowController) -> begin
        function maneuver_button(button_args...; force_disable::Bool = false)::Bool
            disable_button = force_disable || player_is_busy(wnd.mission.player)

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
                new_orientation = get_orientation(wnd.mission.player) >> turn
                player_start_turning(wnd.mission.player, new_orientation)
            end
            CImGui.SameLine()
            CImGui.Dummy(BUTTON_SIZE[1] * 1.0, 1)
            CImGui.SameLine()
            if maneuver_button("-->", BUTTON_SIZE)
                turn = fquat(get_up_vector(), deg2rad(TURN_INCREMENT_DEG))
                new_orientation = get_orientation(wnd.mission.player) >> turn
                player_start_turning(wnd.mission.player, new_orientation)
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
        current_grid_direction = grid_dir(get_orientation(wnd.mission.player))
        current_move_dir = CabMovementDir(current_grid_direction, next_move_flip)
        (MOVE_FORWARD, MOVE_CLIMB, MOVE_DROP) = LEGAL_MOVES
        (forward_is_legal, climb_is_legal, drop_is_legal) = is_legal.(
            LEGAL_MOVES, Ref(current_move_dir),
            Ref(wnd.mission.player_pos.get_voxel_position()),
            Ref(pos -> is_passable(wnd.mission.grid, pos))
        )
        if maneuver_button("x##Move"; force_disable=!forward_is_legal)
            player_start_moving(wnd.mission.player, MOVE_FORWARD, current_move_dir)
        end
        CImGui.SameLine()
        CImGui.Dummy(10, 0)
        CImGui.SameLine()
        if maneuver_button("^^##Move"; force_disable=!climb_is_legal)
            player_start_moving(wnd.mission.player, MOVE_CLIMB, current_move_dir)
        end
        CImGui.SameLine()
        CImGui.Dummy(10, 0)
        CImGui.SameLine()
        if maneuver_button("V##Move"; force_disable=!drop_is_legal)
            player_start_moving(wnd.mission.player, MOVE_DROP, current_move_dir)
        end

        CImGui.Dummy(0, 50)

        # Provide buttons for drilling.
        function is_drill_legal(canonical_dir::Vec3)
            world_dir::v3f = rotate_cab_movement(convert(v3f, canonical_dir),
                                                    current_move_dir)
            drilled_pos = wnd.mission.player_pos.get_precise_position() + world_dir
            drilled_grid_pos = grid_idx(drilled_pos)
            return exists(component_at!(wnd.mission.grid, drilled_grid_pos, Rock)) #TODO: Drillable component for grid entities
        end
        CImGui.Text("DRILL"); CImGui.SameLine()
        CImGui.Dummy(10, 0); CImGui.SameLine()
        if maneuver_button("*##Drill"; force_disable=!is_drill_legal(v3f(1, 0, 0)))
        #begin
            player_start_drilling(wnd.mission.player, current_grid_direction)
        end
        CImGui.SameLine()
        if maneuver_button("V##Drill"; force_disable=!is_drill_legal(v3f(0, 0, -1)))
        #begin
            player_start_drilling(wnd.mission.player, grid_dir(-get_up_vector()))
        end
        CImGui.SameLine()
        if maneuver_button(">>##Drill6"; force_disable=!is_drill_legal(v3i(0, 1, 0)))
        #begin
            drill_dir = grid_dir(rotate_cab_movement(v3i(0, 1, 0), current_move_dir))
            player_start_drilling(wnd.mission.player, drill_dir)
        end
    end

    return WindowController(
        mission,
        "TurnAndMovement$label_extra",
        window_logic
    )
end