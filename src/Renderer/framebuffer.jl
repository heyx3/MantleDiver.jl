# See 'visuals.md' in the GDD for more info on this setup.

const FOREGROUND_FORMAT = SimpleFormat(
    FormatTypes.uint,
    SimpleFormatComponents.RG,
    SimpleFormatBitDepths.B8
)
const BACKGROUND_FORMAT = SimpleFormat(
    FormatTypes.uint,
    SimpleFormatComponents.R,
    SimpleFormatBitDepths.B16
)

const DEPTH_FORMAT = DepthStencilFormats.depth_32u


const COLOR_BITS = UInt8(4)
const COLOR_PACKED_MAX = (UInt8(1) << COLOR_BITS) - UInt8(1)
const COLOR_BIT_MASK = COLOR_PACKED_MAX

const SHAPE_BITS = UInt8(8) - COLOR_BITS
const SHAPE_PACKED_MAX = (UInt8(1) << SHAPE_BITS) - UInt8(1)
const SHAPE_BIT_MASK = SHAPE_PACKED_MAX

const DENSITY_BITS = UInt8(7)
const DENSITY_PACKED_MAX = (UInt8(1) << DENSITY_BITS) - UInt8(1)
const DENSITY_BIT_MASK = DENSITY_PACKED_MAX


const SHADER_FRAMEBUFFER_PACKING = """
    //The surface properties that shaders should output.
    //Further below is code to pack them for the framebuffer.
    struct MaterialSurface
    {
        uint foregroundShape;

        uint foregroundColor;
        uint backgroundColor;

        float foregroundDensity;
        float backgroundDensity;

        bool isTransparent;
    };

    uint packColor(uint value)
    {
        value = clamp(value, 0, $COLOR_PACKED_MAX)
        value &= $COLOR_BIT_MASK;
        return value;
    }
    uint unpackColor(uint sample)
    {
        return sample & $COLOR_BIT_MASK;
    }

    uint packShape(uint value)
    {
        value = clamp(value, 0, $SHAPE_PACKED_MAX)
        value &= $SHAPE_BIT_MASK;
        value <<= $COLOR_BITS;
        return value;
    }
    uint unpackShape(uint value)
    {
        return (value >> $COLOR_BITS) & $SHAPE_BIT_MASK;
    }

    uint packDensity(float value)
    {
        value *= float($(Int(DENSITY_PACKED_MAX)));
        uint roundedValue = clamp((uint)value, 0, $DENSITY_PACKED_MAX);
        return (roundedValue & $DENSITY_BIT_MASK);
    }
    float unpackDensity(uint sample)
    {
        return float(sample & $DENSITY_BIT_MASK) /
                 float($DENSITY_PACKED_MAX);
    }

    uint2 packForeground(MaterialSurface surf)
    {
        return uint2(
            packShape(surf.foregroundShape) | packShape(surf.foregroundColor),
            packDensity(surf.foregroundDensity) |
              (surf.isTransparent ? 1 : 0) << $DENSITY_BITS
        );
    }
    uint packBackground(MaterialSurface surf, bool isPartiallyOccluded)
    {
        uint color;
        float density;
        if (!isPartiallyOccluded || surf.isTransparent)
        {
            color = surf.backgroundColor;
            density = surf.backgroundDensity;
        }
        else
        {
            color = surf.foregroundColor;
            density = surf.foregroundDensity;
        }

        return packColor(color) | (packDensity(density) << $COLOR_BITS);
    }

    //The 'IsTransparent' flag will come from the foreground surface;
    //    a partially-occluded surface's transparency flag is not recoverable.
    MaterialSurface unpackFramebuffer(uint2 foregroundSample, uint backgroundSample)
    {
        MaterialSurface output;

        output.foregroundShape = unpackShape(foregroundSample.x);
        output.foregroundColor = unpackColor(foregroundSample.x);
        output.foregroundDensity = unpackDensity(foregroundSample.y);
        output.isTransparent = ((foregroundSample.y >> $DENSITY_BITS) == 0) : false : true;

        output.backgroundColor = unpackColor(backgroundSample);
        output.backgroundDensity = unpackDensity(backgroundSample >> $COLOR_BITS);

        return output;
    }
"""


mutable struct WorldViewport
    foreground::Texture
    background::Texture

    foreground_depth::Texture

    foreground_target::Target
    background_target::Target

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
                   foreground_target, background_target)
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
    given a callback that actually issues all the world draw calls
    and a boolean for whether to put the output directly onto the screen.

The callback should take one argument, the `E_RenderPass`,
    and should leave unchanged the render state and active Target.
"
function run_render_passes(viewport::WorldViewport,
                           callback_draw_world,
                           to_screen::Bool)
    GL.set_depth_test(GL.ValueTests.less_than)
    GL.set_depth_writes(true)
    GL.set_blending(GL.make_blend_opaque(GL.BlendStateRGB))

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

    #TODO: Render ascii characters

    if to_screen
        #TODO: Present to screen
    end
end