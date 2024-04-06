mutable struct WorldViewport
    foreground::Texture
    background::Texture

    foreground_depth::Texture

    foreground_target::Target
    background_target::Target

    resolution::v2i

    function Framebuffer(resolution::v2i)
        foreground = Texture(FOREGROUND_FORMAT, resolution)
        foreground_depth = Texture(DEPTH_FORMAT, resolution)
        foreground_target = Target(TargetOutput(tex=foreground),
                                   TargetOutput(tex=foreground_depth))

        background = Texture(BACKGROUND_FORMAT, resolution)
        background_target = Target(TargetOutput(tex=background),
                                   DEPTH_FORMAT)

        return new(foreground, background,
                   foreground_depth,
                   foreground_target, background_target,
                   resolution)
    end
end
function Base.close(wv::WorldViewport)
    for f in fieldnames(typeof(wv))
        v = getfield(wv, f)
        if v isa Resource
            close(v)
        end
    end
end


@enum(RenderPass, foreground, background)

"
Executes the render logic for the world,
    given a callback that actually issues all the world draw calls.

The callback should take one argument, the `E_RenderPass`,
    and should leave unchanged the render state and active Target.

Can draw the final output to the screen, or to the given target's first color output.
"
function run_render_passes(viewport::WorldViewport,
                           assets::Assets,
                           callback_draw_world,
                           output::Optional{GL.Target} = nothing)
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
        # Draw foreground:
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
        GL.target_clear(viewport.background_target,
                        vRGBAu(Val(~zero(UInt32))),
                        1)
        GL.target_clear(viewport.background_target, Float32(1))
        GL.target_activate(viewport.background_target)
        callback_draw_world(RenderPass.background)
    end

    # Render the framebuffer to the given output, as ascii chars.
    output_render_state = GL.RenderState(
        depth_write=false,
        depth_test=GL.ValueTests.pass,
        cull_mode = GL.FaceCullModes.off,
        blend_mode = (rgb=GL.make_blend_opaque(GL.BlendStateRGB),
                      alpha=GL.make_blend_opaque(GL.BlendStateAlpha))
    )
    println("#TODO: Set up UBO's and activate texture handles")
    GL.with_render_state(output_render_state) do
        CLEAR_COLOR = vRGBAf(0, 0, 0, 0)
        local output_size::v2u
        if exists(output)
            output_size = output.size
            GL.target_clear(output, CLEAR_COLOR)
        else
            output_size = get_window_size()
            GL.clear_screen(CLEAR_COLOR)
        end

        GL.target_activate(output)

        simple_graphics = service_BasicGraphics()
        GL.render_mesh(simple_graphics.screen_triangle,
                       assets.shader_render_chars)
    end
end