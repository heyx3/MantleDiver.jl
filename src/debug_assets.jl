const DEBUG_ASSETS_FOLDER = "assets_debug"

"Assets that only exist in debug builds of the game"
mutable struct DebugAssets
    tex_button_play::Texture
    tex_button_pause::Texture
    tex_button_fast_forward::Texture

    uint_tex_display_shader::Program
end
function Base.close(da::DebugAssets)
    for f in fieldnames(typeof(da))
        v = getfield(da, f)
        if v isa AbstractResource
            close(v)
        end
    end
end

function DebugAssets()
    function load_gui_tex(relative_path)::Texture
        pixels = FileIO.load(joinpath(DEBUG_ASSETS_FOLDER, relative_path))
        pixels = convert_pixel.(pixels', vRGBAu8)
        return GL.Texture(
            GL.SimpleFormat(
                GL.FormatTypes.normalized_uint,
                GL.SimpleFormatComponents.RGB,
                GL.SimpleFormatBitDepths.B8
            ),
            pixels
        )
    end

    return DebugAssets(
        load_gui_tex("playButton.png"),
        load_gui_tex("pauseButton.png"),
        load_gui_tex("fastForwardButton.png"),
        Bplus.GL.bp_glsl_str("""
        #START_VERTEX
            //Meant to be drawn with the BasicGraphics screen-triangle
            in vec2 vIn_corner;
            out vec2 vOut_uv;
            void main() {
                gl_Position = vec4(vIn_corner.xy, 0.5, 1.0);
                vOut_uv = 0.5 + (0.5 * vIn_corner);
            }
        #START_FRAGMENT
            in vec2 vOut_uv;
            out vec4 fOut_color;

            uniform usampler2D u_tex;
            uniform uint u_maxPixelValue;

            $SHADER_CODE_UTILS
            uniform vec4 u_colorBias, u_colorScale, u_colorOscillation, u_colorPhase;
            uniform float u_transparentCheckerboardScale;

            void main() {
                uvec4 pixelData = textureLod(u_tex, vOut_uv, 0.0);
                vec4 t = vec4(pixelData) / vec4(u_maxPixelValue);

                vec4 pixelColor = PROCEDURAL_GRADIENT(
                    t,
                    u_colorBias, u_colorScale,
                    u_colorOscillation, u_colorPhase
                );

                //Show a checkerboard pattern underneath transparent pixels.
                vec2 checkerPos = vec2(textureSize(u_tex, 0)) * u_transparentCheckerboardScale;
                ivec2 checkerboardMask2 = ivec2(floor(checkerPos)) % 2;
                float checkerboardMask = (checkerboardMask2.x != checkerboardMask2.y) ? 0.0 : 1.0;
                vec4 checkerboardColor = mix(
                    vec4(0.3, 0.3, 0.3, 1.0),
                    vec4(0.7, 0.7, 0.7, 1.0),
                    checkerboardMask
                );

                fOut_color = vec4(mix(pixelColor.xyz, checkerboardColor.xyz, t.a),
                                   1.0);
            }
        """
    ))
end

"Renders the given uint texture into the given RGBA texture (or screen) using a palette"
function debug_render_uint_texture_viz(assets::DebugAssets,
                                       input::Union{Texture, View},
                                       output::Optional{Target}
                                       ;
                                       uint_max_value::UInt32 = 0x000000ff,
                                       gradient::NTuple{4, v4f} = (
                                           v4f(0.5, 0.5, 0.5, 0.5),
                                           v4f(0.5, 0.5, 0.5, 0.5),
                                           v4f(1.5, 0.3, 2.0, 0.8),
                                           v4f(0.3, 0.5, 0.1, 0.8)
                                       ),
                                       transparency_checkerboard_scale::Float32 = @f32(4))
    set_uniform(assets.uint_tex_display_shader, "u_tex", input)
    set_uniform(assets.uint_tex_display_shader, "u_maxPixelValue", uint_max_value)

    set_uniform.(Ref(assets.uint_tex_display_shader),
                 ("u_colorBias", "u_colorScale", "u_colorOscillation", "u_colorPhase"),
                 gradient)
    set_uniform(assets.uint_tex_display_shader,
                "u_transparentCheckerboardScale", transparency_checkerboard_scale)

    view_activate(input)
    target_activate(output)
        render_mesh(service_BasicGraphics().screen_triangle, assets.uint_tex_display_shader)
    target_activate(nothing)
    view_deactivate(input)
end