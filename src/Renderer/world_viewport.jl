mutable struct WorldViewport
    foreground::Texture
    background::Texture

    foreground_depth::Texture

    foreground_target::Target
    background_target::Target

    resolution::v2i

    ubo_read_data::FrameBufferReadData
    ubo_write_data::FrameBufferWriteData
    ubo_read::Buffer
    ubo_write::Buffer

    function WorldViewport(resolution::v2i)
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
            ubo_read_data, ubo_write_data,
            GL.Buffer(false, ubo_read_data),
            GL.Buffer(true, ubo_write_data)
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
    GL.with_depth_writes(true) do
     GL.with_depth_test(GL.ValueTests.less_than) do
      GL.with_viewport(Math.Box2Di(min=v2i(1, 1),  size=viewport.resolution)) do
       GL.with_culling(GL.FaceCullModes.on) do
        GL.with_blending(GL.make_blend_opaque(GL.BlendStateRGBA)) do
            #begin
            GL.set_uniform_block(viewport.ubo_write, UBO_INDEX_FRAMEBUFFER_WRITE_DATA)

            # Draw foreground:
            viewport.ubo_write_data.foreground_mode = true
            viewport.ubo_write_data.tex_foreground_depth = GL.get_ogl_handle(GL.get_view(assets.blank_depth_tex))
            GL.set_buffer_data(viewport.ubo_write, viewport.ubo_write_data)
            GL.target_clear(viewport.foreground_target,
                            vRGBAu(Val(~zero(UInt32))),
                            1)
            GL.target_clear(viewport.foreground_target, Float32(1))
            GL.target_activate(viewport.foreground_target)
            GL.view_activate(assets.blank_depth_tex)
            callback_draw_world(RenderPass.foreground)
            GL.view_deactivate(assets.blank_depth_tex)

            # Draw background:
            viewport.ubo_write_data.foreground_mode = false
            viewport.ubo_write_data.tex_foreground_depth = GL.get_ogl_handle(GL.get_view(viewport.foreground_depth))
            GL.set_buffer_data(viewport.ubo_write, viewport.ubo_write_data)
            GL.target_clear(viewport.background_target,
                            vRGBAu(Val(~zero(UInt32))),
                            1)
            GL.target_clear(viewport.background_target, Float32(1))
            GL.target_activate(viewport.background_target)
            GL.view_activate(viewport.foreground_depth)
            callback_draw_world(RenderPass.background)
            GL.view_deactivate(viewport.foreground_depth)

            GL.target_activate(nothing)
        end end end end end
end

"
Displays the given framebuffer according to the given settings
    (usually by rendering it as ASCII characters).
"
function post_process_framebuffer(viewport::WorldViewport,
                                  assets::Assets,
                                  settings::ViewportDrawSettings)
    GL.set_uniform_block(viewport.ubo_read, UBO_INDEX_FRAMEBUFFER_READ_DATA)
    GL.set_uniform(assets.shader_render_chars, UNIFORM_NAME_RENDER_MODE, Int(settings.output_mode))

    GL.view_activate(viewport.foreground)
    GL.view_activate(viewport.background)
    GL.view_activate.((assets.chars_atlas, assets.chars_atlas_lookup, assets.palette))

    GL.with_depth_writes(false) do
     GL.with_depth_test(GL.ValueTests.pass) do
      GL.with_culling(GL.FaceCullModes.off) do
       GL.with_blending(GL.make_blend_opaque(GL.BlendStateRGBA)) do
            GL.render_mesh(service_BasicGraphics().screen_triangle,
                           assets.shader_render_chars)
    end end end end

    GL.view_deactivate(viewport.foreground)
    GL.view_deactivate(viewport.background)
    GL.view_deactivate.((assets.chars_atlas, assets.chars_atlas_lookup, assets.palette))
end