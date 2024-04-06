# A component for rendering within a 2D Dear ImGUI view of the world.


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
@component DebugGuiVisuals {abstract} begin
    @configurable function draw_order()::Int64
        p::v3i = get_voxel_position(entity)
        return p.x + (1000 * p.y) + (1000000 * p.z)
    end

    @promise visualize(data::DebugGuiRenderData)
end