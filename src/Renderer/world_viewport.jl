mutable struct WorldViewport
    foreground::Texture
    background::Texture

    foreground_depth::Texture

    foreground_target::Target
    background_target::Target

    resolution::v2i

    ubo_read_data::FrameBufferReadData
    ubo_read::Buffer
    ubo_write::Buffer

    function Framebuffer(resolution::v2i)
        foreground = Texture(FOREGROUND_FORMAT, resolution)
        foreground_depth = Texture(DEPTH_FORMAT, resolution;
                                   sampler=GL.TexSampler{2}(
                                       pixel_filter = PixelFilters.rough,
                                       wrapping = WrapModes.clamp
                                   ))
        foreground_target = Target(TargetOutput(tex=foreground),
                                   TargetOutput(tex=foreground_depth))

        background = Texture(BACKGROUND_FORMAT, resolution)
        background_target = Target(TargetOutput(tex=background),
                                   DEPTH_FORMAT)

        ubo_read_data = FrameBufferReadData(
            GL.get_ogl_handle(GL.get_view(foreground)),
            GL.get_ogl_handle(GL.get_view(background)),
            resolution
        )
        ubo_write_data = FrameBufferWriteData(
            GL.get_ogl_handle(GL.get_view(foreground_depth)),
            true
        )

        return new(
            foreground, background,
            foreground_depth,
            foreground_target, background_target,
            resolution,
            ubo_read_data,
            GL.Buffer(false, [ ubo_read_data ]),
            GL.Buffer(true, [ ubo_write_data ])
        )
    end
end
function Base.close(wv::WorldViewport)
    for f in fieldnames(typeof(wv))
        v = getfield(wv, f)
        if v isa AbstractResource
            close(v)
        end
    end
end

@kwdef mutable struct ViewportDrawSettings
    output_mode::E_FramebufferRenderMode = FramebufferRenderMode.regular
    background_color::vRGBf = vRGBf(0, 0, 0)
    background_alpha::Float32 = 0
end


@bp_enum(RenderPass,
    foreground,
    background
)

"
Executes the render logic for the world,
    given a callback that actually issues all the world draw calls.

The callback should take one argument, the `E_RenderPass`,
    and should leave unchanged the render state and active Target.
"
function render_to_framebuffer(callback_draw_world,
                               viewport::WorldViewport,
                               assets::Assets)
    game_render_state = GL.RenderState(
        depth_write=true,
        depth_test=GL.ValueTests.less_than,
        viewport=Math.Box2Di(
            min=v2i(1, 1),
            size=viewport.resolution
        ),
        cull_mode=GL.FaceCullModes.backwards,
        blend_mode = (rgb=GL.make_blend_opaque(GL.BlendStateRGB),
                      alpha=GL.make_blend_opaque(GL.BlendStateAlpha))
    )
    GL.with_render_state(game_render_state) do
        GL.set_uniform_block(viewport.ubo_write, UBO_INDEX_FRAMEBUFFER_WRITE_DATA)

        # Draw foreground:
        GL.set_buffer_data(viewport.ubo_write, Ref(FrameBufferWriteData(
            GL.get_ogl_handle(GL.get_view(assets.blank_depth_tex)),
            true
        )))
        GL.target_clear(viewport.foreground_target,
                        vRGBAu(Val(~zero(UInt32))),
                        1)
        GL.target_clear(viewport.foreground_target,
                        vRGBAu(Val(~zero(UInt32))),
                        2)
        GL.target_clear(viewport.foreground_target, Float32(1))
        GL.target_activate(viewport.foreground_target)
        callback_draw_world(RenderPass.foreground)

        # Draw background:
        GL.set_buffer_data(viewport.ubo_write, Ref(FrameBufferWriteData(
            GL.get_ogl_handle(GL.get_view(viewport.foreground_depth)),
            false
        )))
        GL.target_clear(viewport.background_target,
                        vRGBAu(Val(~zero(UInt32))),
                        1)
        GL.target_clear(viewport.background_target, Float32(1))
        GL.target_activate(viewport.background_target)
        callback_draw_world(RenderPass.background)
    end
    GL.target_activate(nothing)
end

"
Displays the given framebuffer according to the given settings
    (usually by rendering it as ASCII characters).
"
function post_process_framebuffer(viewport::WorldViewport,
                                      assets::Assets,
                                      settings::ViewportDrawSettings)
    GL.set_uniform_block(viewport.ubo_read, UBO_INDEX_FRAMEBUFFER_READ_DATA)
    GL.view_activate(viewport.foreground)
    GL.view_activate(vieport.background)

    output_render_state = GL.RenderState(
        depth_write=false,
        depth_test=GL.ValueTests.pass,
        cull_mode = GL.FaceCullModes.off,
        blend_mode = (rgb=GL.make_blend_opaque(GL.BlendStateRGB),
                      alpha=GL.make_blend_opaque(GL.BlendStateAlpha))
    )
    GL.with_render_state(output_render_state) do
        GL.set_uniform(assets.shader_render_chars,
                       UNIFORM_NAME_RENDER_MODE,
                       Int(settings.output_mode))
        GL.render_mesh(service_BasicGraphics().screen_triangle,
                       assets.shader_render_chars)
    end
end