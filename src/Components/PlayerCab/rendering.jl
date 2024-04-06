
@component DebugGuiVisuals_DrillPod <: DebugGuiVisuals {require: WorldOrientation} begin
    body_color::vRGBAf
    radius::Float32
    thickness::Float32

    arrow_color::vRGBAf
    arrow_length_scale::Float32
    arrow_thickness::Float32

    draw_order() = typemax(Int64)
    function visualize(data::DebugGuiRenderData)
        pos::v3f = get_cosmetic_pos(entity)
        rot::fquat = get_cosmetic_rot(entity)
        forward::v3f = q_apply(rot, get_horz_vector(1))

        # Scale the length of the forward vector for the GUI.
        forward = map(sign, forward) * (abs(forward) ^ @f32(2)) * this.arrow_length_scale

        gui_pos = world_to_gui(pos, data)
        gui_forward = world_to_gui(forward, data, true)

        CImGui.ImDrawList_AddCircle(
            data.draw_list,
            gui_pos.xy,
            this.radius,
            CImGui.ImVec4(this.body_color...),
            0,
            this.thickness
        )
        CImGui.ImDrawList_AddLine(
            data.draw_list,
            gui_pos.xy,
            gui_pos.xy + gui_forward.xy,
            CImGui.ImVec4(this.arrow_color...),
            this.arrow_thickness
        )
    end
end