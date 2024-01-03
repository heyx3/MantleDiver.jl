
##   DebugGuiRenderData   ##

struct DebugGuiRenderData
    horizontal_axis::Int
    other_horizontal_axis::Int
    horizontal_depth::Int # WorldPosition along the other horizontal axis

    gui_range::Box2Df
    world_voxel_range::Box2Df # For the chosen horizontal axis, plus vertical axis

    draw_list::Ptr{CImGui.LibCImGui.ImDrawList}

    DebugGuiRenderData(horizontal_axis, depth, gui_range, world_voxel_range, draw_list) = new(
        horizontal_axis,
        mod1(horizontal_axis + 1, 2),
        depth,

        gui_range,
        world_voxel_range,

        draw_list
    )
end

"
Converts a world position/vector/area into GUI space.
The output Z coordinate becomes 'depth'; the GUI panel is at Z=0.
"
function world_to_gui(v::Vec3, data::DebugGuiRenderData, is_vector::Bool = false)::v3f
    v_gui_axes = v3f(
        v[data.horizontal_axis],
        v[3],
        v[data.other_horizontal_axis]
    )
    # Flip the Y component.
    if is_vector
        @set! v_gui_axes.y = -v_gui_axes.y
        return v_gui_axes
    else
        t2 = inv_lerp(
            min_inclusive(data.world_voxel_range),
            max_inclusive(data.world_voxel_range),
            v_gui_axes.xy
        )
        @set! t2.y = @f32(1) - t2.y
        return vappend(
            lerp(min_inclusive(data.gui_range),
                 max_inclusive(data.gui_range),
                 t2),
            v_gui_axes.z
        )
    end
end
function world_to_gui(b::Box3D, data::DebugGuiRenderData)::Box3Df
    (a, b) = (world_to_gui(min_inclusive(b), data),
              world_to_gui(max_inclusive(b), data))
    # Axes may have been flipped.
    (a, b) = minmax(a, b)

    return Box3Df(min=a, max=b)
end


##   Abstract component   ##

# "Something that can be visualized within the Dear ImGUI debug visualization of the world"
@component DebugGuiVisuals {abstract} {require: WorldPosition} begin
    @configurable function draw_order()::Int64
        p::v3i = get_voxel_position(entity)
        return p.x + (1000 * p.y) + (1000000 * p.z)
    end

    @promise visualize(data::DebugGuiRenderData)
end


##   Specific Components   ##

const ROCK_COLOR = vRGBf(93, 76, 82) / 255
const MINERAL_COLORS = PerMineral{vRGBf}(
    vRGBf(141, 191, 179),
    vRGBf(242, 235, 192),
    vRGBf(243, 180, 98),
    vRGBf(240, 96, 96),
    vRGBf(47, 127, 51),
    vRGBf(244, 64, 52)
) / 255
const MINERAL_MAX_COLOR_POINT = @f32(1)
const MINERAL_COLOR_DROPOFF = @f32(1.7)

# "A rock voxel element with a specific color"
@component DebugGuiVisuals_Rock <: DebugGuiVisuals begin
    function visualize(data::DebugGuiRenderData)
        voxel_pos::v3i = get_component(entity, DiscretePosition).get_voxel_position()
        if voxel_pos[data.other_horizontal_axis] == data.horizontal_depth
            world_rect = Box3Df(center=voxel_pos, size=one(v3f))
            gui_rect = world_to_gui(world_rect, data)
            rock = get_component(entity, Rock)

            color::vRGBf = ROCK_COLOR
            for (mineral_color, mineral_strength) in zip(MINERAL_COLORS, rock.minerals)
                color_strength = saturate(mineral_strength / MINERAL_MAX_COLOR_POINT)
                color_strength ^= MINERAL_COLOR_DROPOFF
                color = lerp(color, mineral_color, color_strength)
            end

            CImGui.ImDrawList_AddRectFilled(
                data.draw_list,
                min_inclusive(gui_rect).xy,
                max_inclusive(gui_rect).xy,
                CImGui.ImVec4(color..., 1),
                @f32(4),
                CImGui.LibCImGui.ImDrawFlags_None
            )
        end
    end
end

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