mutable struct WorldViewport
    foreground::Texture
    background::Texture

    foreground_depth::Texture

    foreground_target::Target
    background_target::Target

    char_grid_resolution::v2i
    final_render_resolution::v2i

    ubo_read_data::FrameBufferReadData{Vector{UInt8}}
    ubo_write_data::FrameBufferWriteData{Vector{UInt8}}
    ubo_read::Buffer
    ubo_write::Buffer

    segmentation::Optional{ViewportSegmentation}
    interface::Optional{Interface}

    bloom_downsamples::Vector{Pair{Texture, Target}}
    bloom_blur::DualBlur
    bloom_kernel_buffer::Buffer

    final_render::Texture
    post_render_target::Target

    function WorldViewport(char_grid_resolution::v2i
                           ;
                           segmentation::Optional{Vector{SegmentationLine}} = nothing,
                           interface::Optional{Interface} = nothing,
                           bloom_blur::DualBlur = DualBlur(
                               2,
                               BLUR_KERNELS[:dual_kawase_downscale],
                               BLUR_KERNELS[:dual_kawase_upscale]
                           ))
        foreground = Texture(FOREGROUND_FORMAT, char_grid_resolution)
        foreground_depth = Texture(DEPTH_FORMAT, char_grid_resolution;
                                   sampler=GL.TexSampler{2}(
                                       pixel_filter = PixelFilters.rough,
                                       wrapping = WrapModes.clamp
                                   ))
        foreground_target = Target(TargetOutput(tex=foreground),
                                   TargetOutput(tex=foreground_depth))

        background = Texture(BACKGROUND_FORMAT, char_grid_resolution)
        background_target = Target(TargetOutput(tex=background),
                                   DEPTH_FORMAT)

        ubo_read_data = FrameBufferReadData(
            GL.get_ogl_handle(GL.get_view(foreground)),
            GL.get_ogl_handle(GL.get_view(background)),
            char_grid_resolution
        )
        ubo_write_data = FrameBufferWriteData(
            GL.get_ogl_handle(GL.get_view(foreground_depth)),
            true
        )

        # Set up the downsampled blur textures for Bloom.
        bloom_downsamples = Vector{Pair{Texture, Target}}()
        next_downsample_size::v2i = char_grid_resolution * 2
        for i in 1:bloom_blur.n_iterations
            next_downsample_size = max(1, next_downsample_size ÷ 2)

            tex = Texture(
                SimpleFormat(FormatTypes.float, SimpleFormatComponents.R, SimpleFormatBitDepths.B16),
                next_downsample_size,
                sampler = TexSampler{2}(wrapping=WrapModes.clamp),
                n_mips = 1
            )
            target = GL.Target(TargetOutput(tex=tex), GL.DepthStencilFormats.depth_16u)
            push!(bloom_downsamples, tex=>target)

            if isone(next_downsample_size)
                break
            end
        end

        final_render_resolution = char_grid_resolution * CHAR_PIXEL_SIZE
        final_render = Texture(SpecialFormats.rgb10_a2, final_render_resolution)
        post_render_target = GL.Target(
            [
                TargetOutput(tex=final_render),
                TargetOutput(tex=bloom_downsamples[1][1])
            ],
            GL.DepthStencilFormats.depth_16u
        )

        return new(
            foreground, background,
            foreground_depth,
            foreground_target, background_target,
            char_grid_resolution, final_render_resolution,
            ubo_read_data, ubo_write_data,
            GL.Buffer(false, ubo_read_data),
            GL.Buffer(true, ubo_write_data),
            exists(segmentation) ? ViewportSegmentation(segmentation, 5.0f0) : nothing,
            interface,
            bloom_downsamples, bloom_blur, Buffer(true, BlurKernel),
            final_render, post_render_target
        )
    end
end
function Base.close(wv::WorldViewport)
    for f in fieldnames(typeof(wv))
        v = getfield(wv, f)
        if v isa Union{AbstractResource, ViewportSegmentation, Interface}
            close(v)
        elseif v isa AbstractVector{<:Union{AbstractResource, ViewportSegmentation, Interface}}
            close.(v)
        end
    end
end

const POST_RENDER_TARGET_WITH_BLOOM = [ 1, 2 ]
const POST_RENDER_TARGET_WITHOUT_BLOOM = [ 1, nothing ]

@kwdef mutable struct ViewportDrawSettings
    output_mode::E_FramebufferRenderMode = FramebufferRenderMode.regular
    background_color::vRGBf = vRGBf(0, 0, 0)
    background_alpha::Float32 = 0

    enable_bloom::Bool = true
    bloom_strength_scale::Float32 = 1.0f0

    enable_segmentation::Bool = true
    enable_interface::Bool = true
end


"
Executes the render logic for the world,
    given a callback that actually issues all the world draw calls.

The callback should take one argument, the `E_RenderPass`,
    and should leave unchanged the render state and active Target.

You normally want to call `post_process_framebuffer()` after this.
"
function render_to_framebuffer(callback_draw_world,
                               viewport::WorldViewport,
                               assets::Assets,
                               settings::ViewportDrawSettings)
    GL.with_depth_writes(true) do
     GL.with_depth_test(GL.ValueTests.less_than) do
      GL.with_viewport(Math.Box2Di(min=v2i(1, 1),  size=viewport.char_grid_resolution)) do
       GL.with_culling(GL.FaceCullModes.on) do
        GL.with_blending(GL.make_blend_opaque(GL.BlendStateRGBA)) do
        #begin
            GL.set_uniform_block(viewport.ubo_write, UBO_INDEX_FRAMEBUFFER_WRITE_DATA)

            # Draw foreground:
            viewport.ubo_write_data.foreground_mode = true
            viewport.ubo_write_data.tex_foreground_depth = GL.get_ogl_handle(GL.get_view(assets.blank_depth_tex))
            GL.set_buffer_data(viewport.ubo_write, viewport.ubo_write_data)
            GL.target_clear(viewport.foreground_target,
                            vRGBAu(i -> ~zero(UInt32)),
                            1)
            GL.target_clear(viewport.foreground_target, Float32(1))
            GL.target_activate(viewport.foreground_target)
            GL.view_activate(assets.blank_depth_tex)
            if exists(viewport.interface)
                render_interface(
                    viewport.interface,
                    assets.shader_render_interface_foreground, RenderPass.foreground,
                    viewport.char_grid_resolution
                )
            end
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
            if settings.enable_interface && exists(viewport.interface)
                render_interface(
                    viewport.interface,
                    assets.shader_render_interface_background, RenderPass.background,
                    viewport.char_grid_resolution
                )
            end
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
    screen_triangle_mesh = service_BasicGraphics().screen_triangle
    GL.with_depth_writes(false) do
     GL.with_depth_test(GL.ValueTests.pass) do
      GL.with_culling(GL.FaceCullModes.off) do
       GL.with_blending(GL.make_blend_opaque(GL.BlendStateRGBA)) do
        # Render the chars and initial bloom value.
        #   Uniforms:
        GL.set_uniform_block(viewport.ubo_read, UBO_INDEX_FRAMEBUFFER_READ_DATA)
        GL.set_uniform(assets.shader_render_chars, UNIFORM_NAME_RENDER_MODE, Int(settings.output_mode))
        #   Texture handles:
        GL.view_activate(viewport.foreground)
        GL.view_activate(viewport.background)
        GL.view_activate.((assets.chars_atlas, assets.chars_atlas_lookup, assets.palette))
        #   Output target:
        GL.target_activate(viewport.post_render_target)
        GL.target_configure_fragment_outputs(viewport.post_render_target, POST_RENDER_TARGET_WITH_BLOOM)
        GL.target_clear(viewport.post_render_target, v4f(0, 0, 0, 0), 1)
        GL.target_clear(viewport.post_render_target, v4f(0, 0, 0, 0), 2)
        #   State and draw call:
        GL.render_mesh(screen_triangle_mesh, assets.shader_render_chars)
        #   Clean up:
        GL.view_deactivate(viewport.foreground)
        GL.view_deactivate(viewport.background)
        GL.view_deactivate.((assets.chars_atlas, assets.chars_atlas_lookup, assets.palette))

        # Draw the segmentations.
        if settings.enable_segmentation && exists(viewport.segmentation)
            screen_pixels = size(GL.get_context().state.viewport)
            char_pixels = screen_pixels ÷ viewport.char_grid_resolution
            draw_segmentation(assets.segmentation, viewport.segmentation,
                            char_pixels, screen_pixels)
        end

        if settings.enable_bloom
            GL.set_uniform_block(viewport.bloom_kernel_buffer, UBO_INDEX_BLUR_KERNEL)

            # Downscale+blur the input.
            GL.set_buffer_data(viewport.bloom_kernel_buffer, viewport.bloom_blur.downscale_kernel)
            for dest_i in 2:length(viewport.bloom_downsamples)
                # Set up the source texture.
                src_tex = viewport.bloom_downsamples[dest_i-1][1]
                GL.set_uniform(assets.shader_bloom_blur, "u_sourceTex", src_tex)
                GL.view_activate(src_tex)

                # Set up the destination texture.
                (dest_tex, dest_target) = viewport.bloom_downsamples[dest_i]
                GL.target_activate(dest_target)
                GL.target_clear(dest_target, v4f(0, 0, 0, 0))
                GL.set_uniform(assets.shader_bloom_blur, "u_destTexel", convert(v2f, 1 / dest_tex.size.xy))

                # Draw.
                GL.render_mesh(screen_triangle_mesh, assets.shader_bloom_blur)
                GL.view_deactivate(src_tex)
            end

            # Upscale+blur the input, adding on top of the original downscaled versions.
            GL.set_buffer_data(viewport.bloom_kernel_buffer, viewport.bloom_blur.upscale_kernel)
            for dest_i in (length(viewport.bloom_downsamples)-1):-1:1
                # Set up the source texture.
                src_tex = viewport.bloom_downsamples[dest_i+1][1]
                GL.set_uniform(assets.shader_bloom_blur, "u_sourceTex", src_tex)
                GL.view_activate(src_tex)

                # Set up the destination texture.
                (dest_tex, dest_target) = viewport.bloom_downsamples[dest_i]
                GL.target_activate(dest_target)
                GL.target_clear(dest_target, v4f(0, 0, 0, 0))
                GL.set_uniform(assets.shader_bloom_blur, "u_destTexel", convert(v2f, 1 / dest_tex.size.xy))

                # Draw.
                GL.render_mesh(screen_triangle_mesh, assets.shader_bloom_blur)
                GL.view_deactivate(src_tex)
            end

            # Add the final bloom value to the render.
            GL.with_blending(GL.make_blend_additive(GL.BlendStateRGB),
                             GL.make_blend_opaque(GL.BlendStateAlpha)) do
            #begin
                GL.target_activate(viewport.post_render_target)
                GL.target_configure_fragment_outputs(viewport.post_render_target, POST_RENDER_TARGET_WITHOUT_BLOOM)
                GL.target_clear(viewport.post_render_target, v4f(0, 0, 0, 0))

                simple_blit(viewport.bloom_downsamples[1][1])
            end
        end
    end end end end
end