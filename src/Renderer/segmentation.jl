# Segmentations are border lines drawn between the ASCII chars.

const SHADER_RENDER_SEGMENTATION_LINES = """
    //Draw one vertex per line; geometry shader will expand them into quads.
    #START_VERTEX
        in ivec4 vIn_line;
        out ivec4 gIn_line;
        void main() {
            gIn_line = vIn_line;
            gl_Position = vec4(0, 0, 0, 1); //Dummy value
        }

    #START_GEOMETRY
        layout (points) in;
        layout (triangle_strip, max_vertices=4) out;

        in ivec4 gIn_line[1];

        uniform uvec2 u_charPixelSize,
                      u_screenPixelSize;
        uniform float u_linePixelWidth;

        out vec2 fIn_uv;

        void main() {
            //Char-grid-space data:
            vec2 lineMinChar = vec2(gIn_line[0].xy),
                 lineDeltaChar = vec2(gIn_line[0].zw),
                 lineMaxChar = lineMinChar + lineDeltaChar;
            //Screen-pixel-space data:
            vec2 lineMinPixel = lineMinChar * vec2(u_charPixelSize),
                 lineMaxPixel = lineMaxChar * vec2(u_charPixelSize);
            //NDC data:
            vec2 pixelNormalization = 1.0 / vec2(u_screenPixelSize),
                 lineMinNdc = mix(vec2(-1, -1), vec2(1, 1),
                                  lineMinPixel * pixelNormalization),
                 lineMaxNdc = mix(vec2(-1, -1), vec2(1, 1),
                                  lineMaxPixel * pixelNormalization);
            //Perpendicular direction to the line:
            vec2 lineDir = sign(lineDeltaChar),
                 perpendicularDir = vec2(-lineDir.y, lineDir.x),
                 perpendicularNdc = perpendicularDir * (u_linePixelWidth * pixelNormalization);
                                        // * 2 for NDC, / 2 for half-width, canceling out

            //Generate the quad for this line.
            for (int vertID = 0; vertID < 4; ++vertID)
            {
                fIn_uv = vec2(
                    float(vertID / 2),
                    float(vertID % 2)
                );
                gl_Position = vec4(
                    mix(lineMinNdc, lineMaxNdc, fIn_uv.y) +
                      mix(-perpendicularNdc, perpendicularNdc, fIn_uv.x),
                    0.5, 1.0
                );
                EmitVertex();
            }
            EndPrimitive();
        }

    #START_FRAGMENT
        in vec2 fIn_uv;
        out vec4 fOut_color;
        out vec4 fOut_bloomInit;
        void main() {
            fOut_color = vec4(0.7, 0.7, 0.7, 0.8);
            fOut_bloomInit = vec4(0, 0, 0, 0);
        }
"""

mutable struct SegmentationAssets
    lines_shader::Program
    SegmentationAssets() = new(
        GL.bp_glsl_str(SHADER_RENDER_SEGMENTATION_LINES)
    )
end
Base.close(sa::SegmentationAssets) = close.((
    sa.lines_shader,
))


primitive type SegmentationLine 128 end
"
Creates a straight-line segmentation piece,
    starting at the min corner of the given char grid cell
    and continuing along the given number of grid cells along a single axis.
"
function SegmentationLine(start::Vec2{<:Integer}, char_delta::Vec2{<:Signed})
    @d8_assert(any(iszero, char_delta) && any(f -> !iszero(f), char_delta),
               "char_delta should be axis-aligned and non-zero, but it's ", char_delta)
    return reinterpret_bytes(v4i(start..., char_delta...), SegmentationLine)
end
@bp_check(sizeof(SegmentationLine) == sizeof(v4u))

mutable struct ViewportSegmentation
    lines_buffer::GL.Buffer
    lines_mesh::GL.Mesh
    lines_pixel_thickness::Float32
    function ViewportSegmentation(lines::Vector{SegmentationLine}, lines_pixel_thickness::Real)
        lines_buffer = GL.Buffer(false, lines)
        lines_mesh = GL.Mesh(
            GL.PrimitiveTypes.point,
            [ GL.VertexDataSource(lines_buffer, sizeof(SegmentationLine), 0) ],
            [ GL.VertexAttribute(1, 0, GL.VSInput(v4i)) ]
        )
        return new(lines_buffer, lines_mesh, lines_pixel_thickness)
    end
end
Base.close(vs::ViewportSegmentation) = close.((
    vs.lines_mesh, vs.lines_buffer
))


function draw_segmentation(assets::SegmentationAssets,
                           view::ViewportSegmentation,
                           char_pixel_size::Vec2{<:Integer},
                           screen_pixel_size::Vec2{<:Integer})
    set_uniform(assets.lines_shader, "u_charPixelSize", convert(v2u, char_pixel_size))
    set_uniform(assets.lines_shader, "u_screenPixelSize", convert(v2u, screen_pixel_size))
    set_uniform(assets.lines_shader, "u_linePixelWidth", view.lines_pixel_thickness)

    GL.with_depth_writes(false) do
     GL.with_depth_test(GL.ValueTests.pass) do
      GL.with_culling(GL.FaceCullModes.off) do
       GL.with_blending(GL.make_blend_alpha(GL.BlendStateRGB), GL.make_blend_opaque(GL.BlendStateAlpha)) do
        #begin
        GL.render_mesh(view.lines_mesh, assets.lines_shader)
    end end end end

    return nothing
end