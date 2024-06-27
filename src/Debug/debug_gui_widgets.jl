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

    # Post-process modes:
    render_mode::E_FramebufferRenderMode

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
        FramebufferRenderMode.regular,
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


###########################################
##   Main game view

function gui_debug_main_view(gui::DebugGui, mission::Mission, rendered_game::Target)
    game_view_tab_region = get_imgui_current_drawable_region()
    draw_list = CImGui.GetForegroundDrawList()

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
            rendered_game.size.x +
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
            # Note that colors are ABGR!
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

    CImGui.Text("Render mode:")
    function render_mode_option(name::String, value::E_FramebufferRenderMode)
        CImGui.SameLine()
        if CImGui.RadioButton(name, gui.render_mode == value)
            gui.render_mode = value
        end
    end
    render_mode_option("Final", FramebufferRenderMode.regular)
    render_mode_option("Chars", FramebufferRenderMode.char_greyscale)
    render_mode_option("FG Shape", FramebufferRenderMode.foreground_shape)
    render_mode_option("FG Color", FramebufferRenderMode.foreground_color)
    render_mode_option("FG Density", FramebufferRenderMode.foreground_density)
    render_mode_option("BG Color", FramebufferRenderMode.background_color)
    render_mode_option("BG Density", FramebufferRenderMode.background_density)
    render_mode_option("Transparency", FramebufferRenderMode.is_foreground_transparent)

    CImGui.Image(GUI.gui_tex_handle(rendered_game.attachment_colors[1].tex),
                 convert(v2f, rendered_game.size),
                 # Flip UV y:
                 (0,1), (1,0))
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
        return exists(component_at!(mission.grid, drilled_grid_pos, Rock))
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
    let tex = gui.background_viz_target.attachment_colors[1].tex
        debug_render_uint_texture_viz(
            debug_assets,
            mission.player_viewport.background,
            gui.background_viz_target
        )
        show_tex("Player View: Background", tex, true)
    end
    let tex = mission.player_viewport.foreground_depth
        show_tex("Player View: Foreground Depth", tex, true)
    end
    show_tex("Char Atlas", assets.chars_atlas, true)
    show_tex("Char UV Lookup", assets.chars_atlas_lookup)
    show_tex("Palette", assets.palette)
end


###############################################
##   OpenGL resource visualizations

function short_type_name(T)::String
    s = string(T)

    # If it has type params, shorten each token separately.
    (name, type_params...) = map(split(s, ('{', '}'))) do token
        last_dot_pos = findlast('.', token)
        return if exists(last_dot_pos)
            token[last_dot_pos+1 : end]
        else
            token
        end
    end
    s = if isempty(type_params)
        name
    else
        "$name{$(join(type_params, ", "))}"
    end

    return s
end

function gui_visualize_resources(gui::DebugGui, debug_assets::DebugAssets,
                                 mission::Mission, assets::Assets)
    basic_graphics::Bplus.BplusApp.Service_BasicGraphics = service_BasicGraphics()
    gui_visualize_resource_category("B+ Globals", [
        "Screen Triangle UVs" => BufferAsStruct(
            basic_graphics.screen_triangle.vertex_data_sources[1].buf,
            StaticBlockArray{3, v2f}
        ),
        "Screen Triangle Mesh" => basic_graphics.screen_triangle,

        "Screen Quad UVs" => BufferAsStruct(
            basic_graphics.screen_quad.vertex_data_sources[1].buf,
            StaticBlockArray{4, v2f}
        ),
        "Screen Quad Mesh" => basic_graphics.screen_quad,

        "Blit shader" => basic_graphics.blit,
        "Empty mesh" => basic_graphics.empty_mesh
    ])

    gui_visualize_resource_category("Game Globals", [
        "Char Palette" => assets.palette,
        "Char Atlas" => assets.chars_atlas,
        "Char Atlas Lookup" => assets.chars_atlas_lookup,
        "Char UBO" => BufferAsStruct(
            assets.chars_ubo,
            CharRenderAssetBuffer
        ),
        "Char Render Shader" => assets.shader_render_chars,
        "Blank Depth Tex" => assets.blank_depth_tex
    ])

    gui_visualize_resource_category("Mission", [
        "Player Cam UBO" => BufferAsStruct(
            mission.player_camera_ubo,
            CameraDataBuffer
        ),
        "Player View Foreground Tex" => mission.player_viewport.foreground,
        "Player View Background Tex" => mission.player_viewport.background,
        "Player View Sampling UBO" => BufferAsStruct(
            mission.player_viewport.ubo_read,
            FrameBufferReadData
        ),
        "Player View Rendering UBO" => BufferAsStruct(
            mission.player_viewport.ubo_write,
            FrameBufferWriteData
        )
    ])

    try_rocks = get_component(mission.ecs, Renderable_Rock)
    if exists(try_rocks)
        rocks::Renderable_Rock = try_rocks[1]
        gui_visualize_resource_category("Mission rocks", [
            "Rock shader" => rocks.shader,
            (string(idx) => buf  for (idx, (chunk, buf)) in rocks.rock_data_buffers)...
        ])
    end

    return nothing
end

function gui_visualize_resource_category(name::String, named_resources::Vector)
    return GUI.gui_within_fold(name) do
        for (name, resource) in named_resources
            fg_color = GUI.gVec4(gui_resource_color(typeof(resource))...)
            GUI.gui_with_style_color(CImGui.LibCImGui.ImGuiCol_Text, fg_color) do
                CImGui.Text("$(short_type_name(typeof(resource))) $name ($(get_ogl_handle(resource))):")
                CImGui.SameLine()
                gui_visualize_resource(resource)
            end
        end
    end
end

gui_resource_color(::Type) = (1, 0, 1, 1)
gui_resource_color(::Type{GL.Program}) = (0.9, 0.9, 0.9, 1)
gui_resource_color(::Type{GL.Texture}) = (0.6, 0.9, 1.0, 1)
gui_resource_color(::Type{GL.View}) = (0.7, 1.0, 1.0, 1)
gui_resource_color(::Type{GL.Buffer}) = (0.2, 0.9, 0.3, 1)
gui_resource_color(::Type{GL.Mesh}) = (0.6, 1.0, 0.6, 1)


gui_visualize_resource(r) = CImGui.Text(string(r))

gui_visualize_resource(p::GL.Program) = GUI.gui_within_fold("$(length(p.uniforms)) uniforms, $(length(p.uniform_blocks)) UBO's, $(length(p.storage_blocks)) SSBO's") do
    CImGui.Text("Uniforms:")
    GUI.gui_with_indentation() do 
        for (name, data) in p.uniforms
            CImGui.Text("$name: $(data.type)")
        end
        if isempty(p.uniforms)
            CImGui.Text("[none]")
        end
    end

    CImGui.Text("UBO's:")
    GUI.gui_with_indentation() do
        for (name, data) in p.uniform_blocks
            CImGui.Text("$name: $(data.byte_size) bytes")
        end
        if isempty(p.uniform_blocks)
            CImGui.Text("[none]")
        end
    end

    CImGui.Text("SSBO's:")
    GUI.gui_with_indentation() do
        for (name, data) in p.storage_blocks
            CImGui.Text("$name: $(data.byte_size) bytes")
        end
        if isempty(p.storage_blocks)
            CImGui.Text("[none]")
        end
    end
end

#TODO: Optionally query a texture's pixels
function gui_visualize_resource(t::GL.Texture)
    description = string(
        if t.type == TexTypes.oneD
            "1D ($(t.size.x) pixels)"
        elseif t.type == TexTypes.twoD
            "$(t.size.x)x$(t.size.y)"
        elseif t.type == TexTypes.threeD
            "3D $(t.size.x)x$(t.size.y)$(t.size.z)"
        elseif t.type == TexTypes.cube_map
            "Cube $(t.size.x)x$(t.size.x)"
        else
            "UNKNOWN_TYPE($(t.type), $(t.size))"
        end,
        " ", string(GL.get_ogl_enum(t.format))[3:end]
    )
    GUI.gui_within_fold(description) do
        CImGui.Text("N Mips: $(t.n_mips)")

        CImGui.Text("Allocated views: ")
        GUI.gui_with_indentation() do
            for (view_params, view) in t.known_views
                CImGui.Text("$(GL.get_ogl_handle(view)):")
                CImGui.SameLine()
                if exists(view_params)
                    gui_visualize_resource(view_params)
                else
                    CImGui.Text("[default]")
                end
            end
            if isempty(t.known_views)
                CImGui.Text("[none yet]")
            end
        end

        CImGui.Text("Default sampler: ")
        CImGui.SameLine()
        gui_visualize_resource(t.sampler)

        if exists(t.depth_stencil_sampling)
            CImGui.Text("Depth/Stencil hybrid mode: $(t.depth_stencil_sampling)")
        end

        if t.swizzle != SwizzleRGBA()
            CImGui.Text("Swizzling: $(t.swizzle)")
        end
    end
end

function gui_visualize_resource(s::GL.TexSampler)
    DEFAULT_SAMPLER = typeof(s)()
    CImGui.Text(string(
        "<",

        if exists(s.depth_comparison_mode)
            "depthCompare=$(s.depth_comparison_mode) "
        else
            ""
        end,

        if s.wrapping isa E_WrapModes
            s.wrapping
        elseif all(w == s.wrapping[1] for w in s.wrapping)
            s.wrapping[0]
        else
            "($(join(s.wrapping, "x")))"
        end,

        " pixels=", s.pixel_filter,
        if isnothing(s.mip_filter)
            " (no mips)"
        else
            " mips=$(s.mip_filter)"
        end,

        if !isone(s.anisotropy)
            " aniso=$(s.anisotropy)"
        else
            ""
        end,

        let has_mip_offset = !iszero(s.mip_offset),
            has_mip_range = (s.mip_range != DEFAULT_SAMPLER.mip_range)
            if !has_mip_offset && !has_mip_range
                ""
            elseif !has_mip_offset
                " mips=[$(min_inclusive(s.mip_range)) to $(max_exclusive(s.mip_range))]"
            elseif !has_mip_range
                " mip+=$(s.mip_offset)"
            else
                " outMip=clamp(mip+$(s.mip_offset), $(min_inclusive(s.mip_range)), $(max_exclusive(s.mip_range)))"
            end
        end,

        if s.cubemap_seamless != DEFAULT_SAMPLER.cubemap_seamless
            if s.cubemap_seamless
                " seamlessCubemapping"
            else
                " roughCubemapping"
            end
        else
            ""
        end,

        ">"
    ))
end
function gui_visualize_resource(vp::GL.SimpleViewParams)
    changes_mip::Bool = (vp.mip_level != 1)
    picks_layer::Bool = exists(vp.layer)
    changes_format::Bool = exists(vp.apparent_format)
    CImGui.Text(
        if !changes_mip && !picks_layer && !changes_format
            "< Plain Image (non-sampling) view >"
        else
            string(
                "< Image (non-sampling) view: ",
                changes_mip ? " mip=$(vp.mip_level)" : "",
                picks_layer ? " layer=$(vp.layer)" : "",
                changes_format ? "format=$(string(GL.get_ogl_enum(vp.apparent_format))[3:end])" : "",
                " >"
            )
        end
    )
end

gui_visualize_resource(b::GL.Buffer) = CImGui.Text(string(b.is_mutable_from_cpu ? "" : "CPU-Immutable, ",
                                                           b.byte_size, " bytes"))

function gui_visualize_resource(m::GL.Mesh)
    GUI.gui_within_fold(string(m.type, "; ",
                        exists(m.index_data) ? "indexed; " : "",
                        length(m.vertex_data_sources), " vertex buffers; ",
                        length(m.vertex_data), "vertex attributes")) do
        CImGui.Text("Vertex buffers:")
        GUI.gui_with_indentation() do
            for source in m.vertex_data_sources
                CImGui.Text(string(
                    "<",
                    " handle=$(GL.get_ogl_handle(source.buf))",
                    (iszero(source.buf_byte_offset) ?  "" : " byteOffset=$(source.buf_byte_offset)"),
                    " elementByteSize=$(source.element_byte_size)",
                    " >"
                ))
            end
        end

        CImGui.Text("Vertex attributes:")
        GUI.gui_with_indentation() do
            for a in m.vertex_data
                CImGui.Text(string(
                    "<",
                    (iszero(a.per_instance) ? "" : "perInstance=$(Int(a.per_instance))"),
                    " vertBufferIdx=$(a.data_source_idx)",
                    " fieldByteOffset=$(a.field_byte_offset)",
                    " type=$(a.field_type)", #TODO: Pretty-printing for vertex data type
                    " >"
                ))
            end
        end

        if exists(m.index_data)
            CImGui.Text(string(
                "Indices: <",
                " type=", m.index_data.type,
                " buffer=", m.index_data.buffer,
                ">"
            ))
        end
    end
end

"
Decorator to visualize a buffer as storing some kind of data structure.
If it's an array, use `StaticBlockArray{N, T}`.
"
struct BufferAsStruct
    b::Buffer
    T::Type
end
GL.get_ogl_handle(b::BufferAsStruct) = GL.get_ogl_handle(b.b)
function gui_visualize_resource(bs::BufferAsStruct)
    GUI.gui_with_fold(string("< ",
                             short_type_name(bs.T), ", ",
                             bs.b.is_mutable_from_cpu ? "" : "CPU-Immutable, ",
                             GL.block_byte_size(bs.T), " bytes, ",
                             ">")) do
        data::bs.T = GL.get_buffer_data(bs.b, bs.T)
        gui_visualize_resource(data)
    end
end

function gui_visualize_resource(d::GL.AbstractOglBlock)
    GUI.gui_with_indentation() do
        for name in propertynames(d)
            value = getproperty(d, name)
            CImGui.Text("$name: $value")
        end
    end
end
function gui_visualize_resource(a::GL.StaticBlockArray{N, T}) where {N, T}
    for i in 1:N
        CImGui.Text("$i: ")
        CImGui.SameLine()
        gui_visualize_resource(a[i])
    end
end