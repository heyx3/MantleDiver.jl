# Various GUI widgets for drawing debug-mode data.

@bp_enum(DebugGuiSpeed,
    play,
    pause,
    fast_forward
)

mutable struct DebugGui
    # Gameplay speed control:
    gameplay_speed::E_DebugGuiSpeed
    fast_forward_speed::Int32

    # Debug rendering the game:
    game_view_sorted_elements::Vector{Tuple{DebugGuiVisuals, Entity, Int64}}

    # Debug maneuver interface:
    maneuver_next_move_flip::Int8

    # Texture visualization panel:
    tex_viz_min_length::Float32
    foreground_viz_target::Target
    background_viz_target::Target

    DebugGui() = new(
        DebugGuiSpeed.play, 3,
        [ ], 1,
        128,
        Target(
            v2u(512, 512),
            SimpleFormat(FormatTypes.normalized_uint,
                         SimpleFormatComponents.RGBA,
                         SimpleFormatBitDepths.B8),
            DepthStencilFormats.depth_16u
        ),
        Target(
            v2u(512, 512),
            SimpleFormat(FormatTypes.normalized_uint,
                         SimpleFormatComponents.RGBA,
                         SimpleFormatBitDepths.B8),
            DepthStencilFormats.depth_16u
        )
    )
end
Base.close(dg::DebugGui) = close.((
    dg.foreground_viz_target,
    dg.background_viz_target
))


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


##########################################
##   Game Speed Controls

function gui_game_speed(gui::DebugGui, assets::DebugAssets)
    gui_with_nested_id("SpeedControls") do
        for speed::E_DebugGuiSpeed in DebugGuiSpeed.instances()
            tex::Texture = if speed == DebugGuiSpeed.play
                assets.tex_button_play
            elseif speed == DebugGuiSpeed.pause
                assets.tex_button_pause
            elseif speed == DebugGuiSpeed.fast_forward
                assets.tex_button_fast_forward
            else
                error("Unhandled: ", speed)
            end
            tint = if speed == gui.gameplay_speed
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
                    gui.gameplay_speed = speed
                end
            end
            CImGui.SameLine()
        end

        CImGui.Dummy(40, 0.001)
        CImGui.SameLine()

        @c CImGui.SliderInt(
            "Fast-Forward Speed", &gui.fast_forward_speed,
            1, 10
        )

        # Undo the last SameLine()
        CImGui.Dummy(0.0001, 0.0001)
    end
end


###############################################
##   Texture asset visualizations

function gui_visualize_textures(gui::DebugGui, debug_assets::DebugAssets,
                                mission::Mission, assets::Assets)
    @c CImGui.SliderFloat(
        "Min Size", &gui.tex_viz_min_length,
        1, 1024
    )

    function show_tex(name::String, tex::GL.Texture,
                      # Render targets need their Y coordinate flipped going from OpenGL to Dear ImGUI.
                      flip_uv_y::Bool = false)
        view = GL.get_view(tex, GL.TexSampler{2}(
            pixel_filter=GL.PixelFilters.rough,
            mip_filter=GL.PixelFilters.rough
        ))
        handle = GUI.gui_tex_handle(view)
        size::v2u = GL.tex_size(tex)

        # If the texture is very small, blow it up.
        scale_up_ratio = gui.tex_viz_min_length / min(size)
        draw_size::v2f = if scale_up_ratio > 1
            size * scale_up_ratio
        else
            size
        end

        # If the texture is very big, shrink it down.
        scale_down_ratio = 256 / max(size)
        if scale_down_ratio < 1
            draw_size *= scale_down_ratio
        end

        CImGui.Text(name * " ($(size.x)x$(size.y)) (as $(draw_size.x)x$(draw_size.y))")
        CImGui.Image(handle, draw_size,
                     (0, flip_uv_y ? 1 : 0),
                     (1, flip_uv_y ? 0 : 1))
        CImGui.Spacing()
    end
    let tex = gui.foreground_viz_target.attachment_colors[1].tex
        debug_render_uint_texture_viz(
            debug_assets,
            mission.player_viewport.foreground,
            gui.foreground_viz_target
        )
        show_tex("Player View: Foreground", tex, true)
    end
    let tex = mission.player_viewport.foreground_depth
        show_tex("Player View: Foreground Depth", tex, true)
    end
    let tex = gui.background_viz_target.attachment_colors[1].tex
        debug_render_uint_texture_viz(
            debug_assets,
            mission.player_viewport.background,
            gui.background_viz_target
        )
        show_tex("Player View: Background", tex, true)
    end
    show_tex("Char Atlas", assets.chars_atlas, true)
    show_tex("Char UV Lookup", assets.chars_atlas_lookup)
    show_tex("Palette", assets.palette)
end