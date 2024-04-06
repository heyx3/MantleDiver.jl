# Various GUI widgets for drawing debug-mode data.

mutable struct DebugGui
    game_view_sorted_elements::Vector{Tuple{DebugGuiVisuals, Entity, Int64}}
    maneuver_next_move_flip::Int8

    DebugGui() = new([ ], 1)
end


############################################
##   Debug game view

function gui_debug_game_view(im_gui_draw_space::Box2Df, mission::Mission, horizontal_axis::Int,
                             gui::DebugGui)
    other_x_axis::Int = mod1(horizontal_axis + 1, 2)

    # Presort drawn elements by their priority.
    empty!(gui.game_view_sorted_elements)
    for (component, entity) in get_components(mission.ecs, DebugGuiVisuals)
        push!(gui.game_view_sorted_elements,
            (component, entity, component.draw_order()))
    end
    sort!(gui.game_view_sorted_elements, by=(data->data[3]))

    # The UI Y axis corresponds to the world Z axis.
    # The UI X axis will correspond to either the X or Y axis.

    # Compute data for drawing the world grid along this slice.
    world_slice_space = Box2Df(
        center = let center3D = mission.player_pos.get_precise_position()
            Vec(center3D[horizontal_axis], center3D[3])
        end,
        size = let size3D = v3i(4, 4, 10)
            Vec(size3D[horizontal_axis], size3D[3])
        end
    )
    gui_render_data = DebugGuiRenderData(
        horizontal_axis,
        mission.player_pos.get_voxel_position()[other_x_axis],
        im_gui_draw_space, world_slice_space,
        CImGui.GetWindowDrawList()
    )

    # Draw the background.
    CImGui.ImDrawList_AddRectFilled(
        CImGui.GetWindowDrawList(),
        min_inclusive(im_gui_draw_space),
        max_inclusive(im_gui_draw_space),
        CImGui.ImVec4(0.7, 0.7, 0.7, 0.7),
        @f32(4),
        CImGui.LibCImGui.ImDrawFlags_None
    )

    # Draw all elements.
    GUI.gui_with_clip_rect(gui_render_data.gui_range, false, gui_render_data.draw_list) do
        for (component, entity, _) in gui.game_view_sorted_elements
            component.visualize(gui_render_data)
        end
    end
end

function gui_debug_game_views(im_gui_draw_space::Box2Df, mission::Mission, gui::DebugGui)
    DRAW_BORDER = 10
    sub_view_size::v2f = (size(im_gui_draw_space) * v2f(0.5, 1)) -
                         (DRAW_BORDER * 2)
    gui_debug_game_view(Box2Df(min=min_inclusive(im_gui_draw_space) + DRAW_BORDER,
                               size=sub_view_size),
                        mission,
                        1, gui)
    gui_debug_game_view(Box2Df(min=Vec(center(im_gui_draw_space).x,
                                       min_inclusive(im_gui_draw_space).y)
                                    + DRAW_BORDER,
                               size=sub_view_size),
                        mission,
                        2, gui)
end


##########################################
##   Maneuvers


const TURN_INCREMENT_DEG = @f32(30)

function gui_debug_maneuvers(mission::Mission, gui::DebugGui)
    function maneuver_button(button_args...; force_disable::Bool = false)::Bool
        disable_button = force_disable || player_is_busy(mission.player)

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
            new_orientation = get_orientation(mission.player) >> turn
            player_start_turning(mission.player, new_orientation)
        end
        CImGui.SameLine()
        CImGui.Dummy(BUTTON_SIZE[1] * 1.0, 1)
        CImGui.SameLine()
        if maneuver_button("-->", BUTTON_SIZE)
            turn = fquat(get_up_vector(), deg2rad(TURN_INCREMENT_DEG))
            new_orientation = get_orientation(mission.player) >> turn
            player_start_turning(mission.player, new_orientation)
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
    next_move_flip_ui = convert(Cint, inv_lerp_i(-1, +1, gui.maneuver_next_move_flip))
    @c CImGui.SliderInt("Side", &next_move_flip_ui,
                        0, 1,
                        "",
                        CImGui.ImGuiSliderFlags_None)
    gui.maneuver_next_move_flip = convert(Int8, lerp(-1, +1, next_move_flip_ui))

    # Provide buttons for all movements, with the current 'flip' direction.
    current_grid_direction = grid_dir(get_orientation(mission.player))
    current_move_dir = CabMovementDir(current_grid_direction, gui.maneuver_next_move_flip)
    (MOVE_FORWARD, MOVE_CLIMB, MOVE_DROP) = LEGAL_MOVES
    (forward_is_legal, climb_is_legal, drop_is_legal) = is_legal.(
        LEGAL_MOVES, Ref(current_move_dir),
        Ref(mission.player_pos.get_voxel_position()),
        Ref(pos -> is_passable(mission.grid, pos))
    )
    if maneuver_button("x##Move"; force_disable=!forward_is_legal)
        player_start_moving(mission.player, MOVE_FORWARD, current_move_dir)
    end
    CImGui.SameLine()
    CImGui.Dummy(10, 0)
    CImGui.SameLine()
    if maneuver_button("^^##Move"; force_disable=!climb_is_legal)
        player_start_moving(mission.player, MOVE_CLIMB, current_move_dir)
    end
    CImGui.SameLine()
    CImGui.Dummy(10, 0)
    CImGui.SameLine()
    if maneuver_button("V##Move"; force_disable=!drop_is_legal)
        player_start_moving(mission.player, MOVE_DROP, current_move_dir)
    end

    CImGui.Dummy(0, 50)

    # Provide buttons for drilling.
    function is_drill_legal(canonical_dir::Vec3)
        world_dir::v3f = rotate_cab_movement(convert(v3f, canonical_dir),
                                                current_move_dir)
        drilled_pos = mission.player_pos.get_precise_position() + world_dir
        drilled_grid_pos = grid_idx(drilled_pos)
        return exists(component_at!(mission.grid, drilled_grid_pos, Rock)) #TODO: Drillable component for grid entities
    end
    CImGui.Text("DRILL"); CImGui.SameLine()
    CImGui.Dummy(10, 0); CImGui.SameLine()
    if maneuver_button("*##Drill"; force_disable=!is_drill_legal(v3f(1, 0, 0)))
        player_start_drilling(mission.player, current_grid_direction)
    end
    CImGui.SameLine()
    if maneuver_button("V##Drill"; force_disable=!is_drill_legal(v3f(0, 0, -1)))
        player_start_drilling(mission.player, grid_dir(-get_up_vector()))
    end
    CImGui.SameLine()
    if maneuver_button(">>##Drill6"; force_disable=!is_drill_legal(v3i(0, 1, 0)))
        drill_dir = grid_dir(rotate_cab_movement(v3i(0, 1, 0), current_move_dir))
        player_start_drilling(mission.player, drill_dir)
    end
end