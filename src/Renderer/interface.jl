# The run-time interfaces for the game.

"
Some kind of UI rendering and/or logic, wrapped in a `Panel`.

Should implement the following interface:
  * `widget_init!(widget, owning_panel::Panel)::Nothing`
   * Make sure to set the panel's `space` and any other fields you want to customize!
  * **[optional]** `widget_tick!(widget, owning_panel::Panel, delta_seconds::Float32)::Nothing`
  * **[optional]** `widget_kill!(widget, owning_panel::Panel)::Nothing`

Rendering is done by updating the owning panel's `foregrounds` and `backgrounds` fields.
"
abstract type AbstractWidget end

widget_tick!(widget, panel, delta_seconds) = nothing
widget_kill!(widget, panel) = nothing


"An invisible widget"
struct WidgetNull <: AbstractWidget
end
widget_init!(::WidgetNull, panel) = nothing


#####################################
#   Panels

"
A piece of UI.
For type stability, individual widget types are held as nested fields rather than being subtypes of this.

Update it with `panel_tick!(p, delta_seconds)` and clean it up with `panel_kill!(p)`.
Swap out the widget inside the panel using `replace_widget!(p, new_widget)`.
"
mutable struct Panel
    space::Box2Di # Framebuffer pixels this panel occupies, relative to its parent.
    children::Vector{Panel} # Any widgets that are inside, and managed by, this one.
    foregrounds::Dict{v2i, CharForegroundValue} # Char foregrounds to draw, relative to this panel's space.
    backgrounds::Dict{v2i, CharBackgroundValue} # Char backgrounds to draw, relative to this panel's space.
    widget::AbstractWidget # Contains type-unstable behavior for this panel.

    function Panel(::Type{TWidget}, widget_args...; widget_kw_args...) where {TWidget<:AbstractWidget}
        p = new(Box2Di(min=one(v2i), max=one(v2i)),
                Vector{Panel}(),
                Dict{v2i, CharForegroundValue}(),
                Dict{v2i, CharBackgroundValue}(),
                TWidget(widget_args...; widget_kw_args...))
        widget_init!(p.widget, p)
        return p
    end
end

function panel_tick!(p::Panel, delta_seconds::Float32)
    widget_tick!(p.widget, p, delta_seconds)
    for child in p.children
        panel_tick!(child, delta_seconds)
    end
    return nothing
end
function panel_kill!(p::Panel)
    replace_widget!(p, WidgetNull)
    return nothing
end

"Resets this panel to contain the given widget instead of its current one."
function replace_widget!(p::Panel, new_widget_type::Type{<:AbstractWidget},
                         widget_args...
                         ; widget_kw_args...)
    widget_kill!(p.widget, p)

    for child in p.children
        panel_kill!(child)
    end
    empty!(p.children)

    empty!(p.foregrounds)
    empty!(p.backgrounds)
    p.space = Box2Di(min=one(v2i), max=one(v2i))

    p.widget = new_widget_type(widget_args...; widget_kw_args...)
    widget_init!(p.widget, p)

    return nothing
end

"
Traverses this panel and its sub-panels, depth-first.
Runs your lambda on each one, also passing in the panel's screen-space rectangle.
"
function for_panels_depth_first(to_do, p::Panel, screen_rect::Box2Di)
    sub_rect = Box2Di(
        min = min_inclusive(screen_rect) + min_inclusive(p.space) - 1,
        size = size(p.space)
    )
    to_do(p, sub_rect)
    for_panels_depth_first(to_do, p.children, sub_rect)
    return nothing
end
function for_panels_depth_first(to_do, ps::Vector{Panel}, screen_rect::Box2Di)
    for p in ps
        for_panels_depth_first(to_do, p, screen_rect)
    end
    return nothing
end


mutable struct _Interface{TForegroundPixel, TBackgroundPixel}
    panels::Vector{Panel} # Drawn in order, so later panels cover earlier ones

    # Resources used for rendering:
    points_buffer_foreground::Bplus.GL.Buffer
    points_buffer_background::Bplus.GL.Buffer
    foreground_mesh::Bplus.GL.Mesh
    background_mesh::Bplus.GL.Mesh
    foreground_points_to_draw::Vector{TForegroundPixel}
    background_points_to_draw::Vector{TBackgroundPixel}
    n_max_foreground_points::Int
    n_max_background_points::Int
end

function Base.close(i::_Interface)
    panel_kill!.(i.panels)
    close(i.foreground_mesh)
    close(i.background_mesh)
    close(i.points_buffer_foreground)
    close(i.points_buffer_background)
end

function for_panels_depth_first(to_do, i::_Interface, screen_rect::Box2Di)
    return for_panels_depth_first(to_do, i.panels, screen_rect)
end
function for_panels_depth_first(to_do, i::_Interface, screen_size::Vec2{<:Integer})
    return for_panels_depth_first(to_do, i, Box2Di(min=one(v2i), size=screen_size))
end


################################
#   Panel rendering

"The per-vertex data that goes into the panel-rendering foreground shader"
struct InterfaceGpuPointForeground
    pixel::v2u
    density::UInt8
    shape::UInt8
    packed_color_transparency::UInt8
end
InterfaceGpuPointForeground(pixel::Vec2, density_f, shape, color, is_transparent::Bool) = InterfaceGpuPointForeground(
    convert(v2u, pixel),
    floor(UInt8, clamp(density_f * 256, 0, 255)),
    if shape isa E_CharShapeType
        UInt8(shape)
    else
        convert(UInt8, shape)
    end,
    convert(UInt8, color) | (is_transparent ? 0x80 : 0x00)
)
InterfaceGpuPointForeground(pixel::Vec2, char, color, is_transparent::Bool) = InterfaceGpuPointForeground(
    pixel,
    let c = CharForegroundValue(convert(Char, char))
        (c.density, c.shape)
    end...,
    color, is_transparent
)
"Gets the description of the interface foreground pixel data for a `Bplus.GL.Mesh` that has it"
interface_gpu_point_foreground_attributes(data_source_idx::Integer) = Bplus.GL.VertexAttribute.(
    Ref(data_source_idx),
    fieldoffset.(
        Ref(InterfaceGpuPointForeground),
        Base.fieldindex.(InterfaceGpuPointForeground, [
            :pixel,
            :density,
            :packed_color_transparency,
            :shape
        ])
    ),
    [
        Bplus.GL.VSInput(v2u),
        Bplus.GL.VSInput_FVector(Vec{1, UInt8}, true),
        Bplus.GL.VSInput(UInt8),
        Bplus.GL.VSInput(UInt8)
    ]
)

"The per-vertex data that goes into the panel-rendering background shader"
struct InterfaceGpuPointBackground
    pixel::v2u
    density::UInt8
    packed_color_transparency::UInt8
end
InterfaceGpuPointBackground(pixel, density_f, color, is_transparent) = InterfaceGpuPointBackground(
    convert(v2u, pixel),
    floor(UInt8, clamp(density_f * 256, 0, 255)),
    convert(UInt8, color) | (is_transparent ? 0x80 : 0x00)
)
"Gets the description of the interface background pixel data for a `Bplus.GL.Mesh` that has it"
interface_gpu_point_background_attributes(data_source_idx::Integer) = Bplus.GL.VertexAttribute.(
    Ref(data_source_idx),
    fieldoffset.(
        Ref(InterfaceGpuPointBackground),
        Base.fieldindex.(InterfaceGpuPointBackground, [
            :pixel,
            :density,
            :packed_color_transparency
        ])
    ),
    [
        Bplus.GL.VSInput(v2u),
        Bplus.GL.VSInput_FVector(Vec{1, UInt8}, true),
        Bplus.GL.VSInput(UInt8)
    ]
)

const Interface = _Interface{InterfaceGpuPointForeground, InterfaceGpuPointBackground}
function _Interface{InterfaceGpuPointForeground, InterfaceGpuPointBackground}(
             panels,
             initial_foreground_buffer_count::Int = 1024,
             initial_background_buffer_count=initial_foreground_buffer_count
         )
    # Create dummy buffers/meshes, then call the function to resize them.
    interface = _Interface(
        collect(Panel, panels),
        Bplus.GL.Buffer(64, false), Bplus.GL.Buffer(64, false),
        Bplus.GL.Mesh(Bplus.GL.PrimitiveTypes.point, VertexDataSource[ ], VertexAttribute[ ]),
        Bplus.GL.Mesh(Bplus.GL.PrimitiveTypes.point, VertexDataSource[ ], VertexAttribute[ ]),
        Bplus.Utilities.preallocated_vector(InterfaceGpuPointForeground, initial_foreground_buffer_count),
        Bplus.Utilities.preallocated_vector(InterfaceGpuPointBackground, initial_background_buffer_count),
        0, 0
    )
    presize_interface_buffers!(interface, initial_foreground_buffer_count, initial_background_buffer_count)
    return interface
end

Base.show(io::IO, ::Type{Interface}) = print(io, "Interface")

"
Re-allocates the interface's GPU buffers
   to handle at least the given number of foreground and background points
"
function presize_interface_buffers!(interface::Interface, n_foreground_points::Int, n_background_points::Int)
    function process(buffer::Bplus.GL.Buffer, mesh::Bplus.GL.Mesh,
                     count::Int, element_byte_size::Int,
                     attributes::Vector{Bplus.GL.VertexAttribute}
                    )::Tuple{Bplus.GL.Buffer, Bplus.GL.Mesh}
        close(mesh)
        close(buffer)

        buffer = Bplus.GL.Buffer(element_byte_size * count, true)
        mesh = Bplus.GL.Mesh(
            Bplus.GL.PrimitiveTypes.point,
            [ Bplus.GL.VertexDataSource(buffer, element_byte_size, 0) ],
            attributes
        )

        return (buffer, mesh)
    end

    if n_foreground_points > interface.n_max_foreground_points
        (interface.points_buffer_foreground, interface.foreground_mesh) = process(
            interface.points_buffer_foreground, interface.foreground_mesh,
            n_foreground_points, sizeof(InterfaceGpuPointForeground),
            interface_gpu_point_foreground_attributes(1)
        )
        interface.n_max_foreground_points = n_foreground_points
    end
    if n_background_points > interface.n_max_background_points
        (interface.points_buffer_background, interface.background_mesh) = process(
            interface.points_buffer_background, interface.background_mesh,
            n_background_points, sizeof(InterfaceGpuPointBackground),
            interface_gpu_point_background_attributes(1)
        )
        interface.n_max_background_points = n_background_points
    end

    return nothing
end


const SHADER_CODE_RENDER_INTERFACE = """
    //Define RENDER_FOREGROUND for foreground rendering or RENDER_BACKGROUND for background rendering.
    #if !defined(RENDER_FOREGROUND) && !defined(RENDER_BACKGROUND)
        #error Must define whether we're doing foreground or background rendering!
    #endif

    $SHADER_CODE_UTILS
    $SHADER_CODE_FRAMEBUFFER_PACKING

    #START_VERTEX
        in uvec2 vIn_Cell;
        in float vIn_Density;
        in uint vIn_ColorAndTransparency;
        #if defined(RENDER_FOREGROUND)
            in uint vIn_Shape;
        #else
            //Nothing extra for background
        #endif

        out uvec2 gIn_Cell;
        out uvec2 gIn_PackedFramebufferData;

        void main() {
            gl_Position = vec4(0, 0, 0, 1);
            gIn_Cell = vIn_Cell;

            //Copy the data to the surface structure, whether foreground or background.
            MaterialSurface surf;
            surf.foregroundColor = (vIn_ColorAndTransparency & 0x7f);
            surf.isTransparent =   (vIn_ColorAndTransparency & 0x80) != 0;
            surf.backgroundColor = surf.foregroundColor;
            surf.foregroundDensity = vIn_Density;
            surf.backgroundDensity = surf.foregroundDensity;
            //Copy buffer-specific data.
            #ifdef RENDER_FOREGROUND
                surf.foregroundShape = vIn_Shape;
                gIn_PackedFramebufferData = packForeground(surf);
            #else
                gIn_PackedFramebufferData = uvec2(packBackground(surf, false), 0);
            #endif
        }

    #START_GEOMETRY
        layout(points) in;
        layout(triangle_strip, max_vertices=4) out;

        in uvec2 gIn_Cell[1];
        in uvec2 gIn_PackedFramebufferData[1];

        uniform uvec2 u_FramebufferSize;

        out flat uvec2 fIn_PackedFramebufferData;

        void main() {
            vec2 texel = 1.0 / vec2(u_FramebufferSize);
            //Note that we are correcting for Julia's 1-based indexing here.
            vec2 cellMinT = vec2(gIn_Cell[0] - 1) * texel,
                 cellMaxT = cellMinT + texel;
            vec4 cellCornersT = vec4(cellMinT, cellMaxT);

            #define GEOM_VERT(X, Y) { \
                fIn_PackedFramebufferData = gIn_PackedFramebufferData[0]; \
                gl_Position = vec4( \
                    clamp(mix(vec2(-1, -1), vec2(1, 1), vec2(cellCornersT.X, cellCornersT.Y)), \
                          vec2(-1, -1), vec2(1, 1)), \
                    0.0000001, 1 \
                ); \
                EmitVertex(); \
            }
            GEOM_VERT(x, y)
            GEOM_VERT(z, y)
            GEOM_VERT(x, w)
            GEOM_VERT(z, w)
            EndPrimitive();
        }

    #START_FRAGMENT
        $UBO_CODE_FRAMEBUFFER_WRITE_DATA

        in flat uvec2 fIn_PackedFramebufferData;
        void main() {
            //Instead of calling 'writeFramebuffer()', we've already packed the data ourselves.
            fOut_packed = uvec4(fIn_PackedFramebufferData, 0, 0);
        }
"""


function update_interface!(interface::Interface, delta_seconds::Float32, resolution::Vec2{<:Integer})
    # Generate the vertex data.
    empty!(interface.foreground_points_to_draw)
    empty!(interface.background_points_to_draw)
    screen_rect = Box2Di(
        min=one(v2i),
        size=resolution
    )
    for_panels_depth_first(interface, screen_rect) do panel::Panel, rect::Box2Di
        for (relative_pos, fore::CharForegroundValue) in panel.foregrounds
            @d8_assert(Bplus.Math.is_touching(rect, relative_pos),
                        typeof(panel.widget), " panel space of ", rect,
                        " doesn't touch one of its relative foreground spots, ", relative_pos)
            absolute_pos = min_inclusive(rect) + relative_pos - 1
            if Bplus.Math.is_touching(screen_rect, convert(v2i, absolute_pos))
                push!(interface.foreground_points_to_draw, InterfaceGpuPointForeground(
                    absolute_pos,
                    fore.density, fore.shape, fore.color, fore.is_transparent
                ))
            end
        end
        for (relative_pos::v2i, back::CharBackgroundValue) in panel.backgrounds
            @d8_assert(Bplus.Math.is_touching(rect, relative_pos),
                        typeof(panel.widget), " panel space of ", rect,
                        " doesn't touch one of its relative background spots, ", relative_pos)
            absolute_pos = min_inclusive(rect) + relative_pos - 1
            if Bplus.Math.is_touching(screen_rect, convert(v2i, absolute_pos))
                push!(interface.background_points_to_draw, InterfaceGpuPointBackground(
                    absolute_pos,
                    back.density, back.color, false
                ))
            end
        end
    end

    # Upload the vertex data.
    presize_interface_buffers!(
        interface,
        length(interface.foreground_points_to_draw),
        length(interface.background_points_to_draw)
    )
    Bplus.GL.set_buffer_data(
        interface.points_buffer_foreground,
        interface.foreground_points_to_draw
    )
    Bplus.GL.set_buffer_data(
        interface.points_buffer_background,
        interface.background_points_to_draw
    )
end
function render_interface(interface::Interface,
                          shader::Bplus.GL.Program,
                          pass::E_RenderPass,
                          resolution::Vec2{<:Integer})
    @d8_assert(in(pass, (RenderPass.foreground, RenderPass.background)),
               "Invalid pass: ", pass)
    is_foreground::Bool = (pass == RenderPass.foreground)

    # Execute the draw call.
    Bplus.GL.set_uniform(shader, "u_FramebufferSize", convert(v2u, resolution))
    Bplus.GL.with_depth_test(Bplus.GL.ValueTests.pass) do
     Bplus.GL.with_depth_writes(true) do
      Bplus.GL.with_blending(Bplus.GL.make_blend_opaque(Bplus.GL.BlendStateRGB)) do
        Bplus.GL.render_mesh(
            is_foreground ? interface.foreground_mesh : interface.background_mesh,
            shader,
            elements = Bplus.Math.IntervalU(
                min=1,
                size=(if is_foreground
                          length(interface.foreground_points_to_draw)
                      else
                          length(interface.background_points_to_draw)
                      end)
            )
        )
    end end end
end