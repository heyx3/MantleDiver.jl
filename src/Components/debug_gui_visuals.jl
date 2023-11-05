"Something that can be visualized within the Dear ImGUI debug visualization of the world"
abstract type AbstractDebugGuiVisualsComponent <: AbstractComponent end

# By default, GUI drawer components require some kind of position data.
ECS.require_components(::Type{<:AbstractDebugGuiVisualsComponent}) = (AbstractVoxelPositionComponent, )

"Lower values should be drawn first"
draw_order(v::AbstractDebugGuiVisualsComponent, e::Entity)::Int64 = let p = get_voxel_position(e)
    p.x + (1000 * p.y) + (1000000 * p.z)
end


##   DebugGuiRenderData   ##

struct DebugGuiRenderData
    horizontal_axis::Int
    other_horizontal_axis::Int
    horizontal_depth::Int # Position along the other horizontal axis

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


##   Interface   ##

"Visualizes a specific element, as part of a 2D slice of the world, in a Dear ImGUI canvas"
function gui_visualize(c::AbstractDebugGuiVisualsComponent, e::Entity, data::DebugGuiRenderData)
    error("gui_visualize(::", typeof(c), ", ...) not implemented")
end


##   Specific Components   ##

"A rock voxel element with a specific color"
mutable struct DebugGuiVisualsComponent_Rock <: AbstractDebugGuiVisualsComponent
end

function gui_visualize(b::DebugGuiVisualsComponent_Rock, e::Entity, data::DebugGuiRenderData)
    voxel_pos::v3i = get_voxel_position(e)
    if voxel_pos[data.other_horizontal_axis] == data.horizontal_depth
        world_rect = Box3Df(center=voxel_pos, size=one(v3f))
        gui_rect = world_to_gui(world_rect, data)
        CImGui.ImDrawList_AddRectFilled(
            data.draw_list,
            min_inclusive(gui_rect).xy,
            max_inclusive(gui_rect).xy,
            if has_component(e, GoldComponent)
                CImGui.ImVec4(0.93, 0.66, 0.05, 1)
            else
                CImGui.ImVec4(0.4, 0.15, 0.01, 1)
            end,
            @f32(4),
            CImGui.LibCImGui.ImDrawFlags_None
        )
    end
end


@kwdef mutable struct DebugGuiVisualsComponent_DrillPod <: AbstractDebugGuiVisualsComponent
    body_color::vRGBAf = Vec(0.2, 1, 0.5, 1)
    radius::Float32 = 10
    thickness::Float32 = 3

    arrow_color::vRGBAf = Vec(1, 0.7, 0.7, 1)
    arrow_length_scale::Float32 = 15
    arrow_thickness::Float32 = 3
end

ECS.require_components(::Type{DebugGuiVisualsComponent_DrillPod}) = (
    AbstractVoxelPositionComponent,
    OrientationComponent
)

draw_order(::DebugGuiVisualsComponent_DrillPod, ::Entity) = typemax(Int64)

function gui_visualize(dp::DebugGuiVisualsComponent_DrillPod, e::Entity, data::DebugGuiRenderData)
    pos::v3f = get_cosmetic_pos(e)
    rot::fquat = get_cosmetic_rot(e)
    forward::v3f = q_apply(rot, get_horz_vector(1))

    # Scale the length of the forward vector for the GUI.
    forward = map(sign, forward) * (abs(forward) ^ @f32(2)) * dp.arrow_length_scale

    gui_pos = world_to_gui(pos, data)
    gui_forward = world_to_gui(forward, data, true)

    CImGui.ImDrawList_AddCircle(
        data.draw_list,
        gui_pos.xy,
        dp.radius,
        CImGui.ImVec4(dp.body_color...),
        0,
        dp.thickness
    )
    CImGui.ImDrawList_AddLine(
        data.draw_list,
        gui_pos.xy,
        gui_pos.xy + gui_forward.xy,
        CImGui.ImVec4(dp.arrow_color...),
        dp.arrow_thickness
    )
end