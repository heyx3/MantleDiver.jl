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

"Defines GLSL utilities for packing and unpacking framebuffer data"
const SHADER_CODE_FRAMEBUFFER_PACKING = """
    #ifndef FRAMEBUFFER_PACKING_H
    #define FRAMEBUFFER_PACKING_H

    //The surface properties that shaders should output.
    //Further below is code to pack and unpack them for the framebuffer.
    struct MaterialSurface
    {
        uint foregroundShape;

        uint foregroundColor;
        uint backgroundColor;

        float foregroundDensity;
        float backgroundDensity;

        bool isTransparent;
    };

    /////////////////////////////////////////

    uint packColor(uint value)
    {
        value = clamp(value, uint(0), uint($COLOR_PACKED_MAX));
        value &= $COLOR_BIT_MASK;
        return value;
    }
    uint unpackColor(uint sampleR)
    {
        return sampleR & $COLOR_BIT_MASK;
    }

    uint packShape(uint value)
    {
        value = clamp(value, uint(0), uint($(Int(SHAPE_PACKED_MAX))));
        value &= $(Int(SHAPE_BIT_MASK));
        value <<= $(Int(COLOR_BITS));
        return value;
    }
    uint unpackShape(uint value)
    {
        return (value >> $(Int(COLOR_BITS))) & $(Int(SHAPE_BIT_MASK));
    }

    uint packDensity(float value)
    {
        value *= float($(Int(DENSITY_PACKED_MAX)));
        uint roundedValue = clamp(uint(value), uint(0), uint($(Int(DENSITY_PACKED_MAX))));
        return (roundedValue & $(Int(DENSITY_BIT_MASK)));
    }
    float unpackDensity(uint sampleR)
    {
        return float(sampleR & $(Int(DENSITY_BIT_MASK))) /
                float($(Int(DENSITY_PACKED_MAX)));
    }

    ////////////////////////////////////////////////////////

    uvec2 packForeground(MaterialSurface surf)
    {
        return uvec2(
            packShape(surf.foregroundShape) |
                packColor(surf.foregroundColor),
            packDensity(surf.foregroundDensity) |
                ((surf.isTransparent ? 1 : 0) << $(Int(DENSITY_BITS)))
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

        return packColor(color) | (packDensity(density) << $(Int(COLOR_BITS)));
    }

    //The 'IsTransparent' flag will come from the foreground surface;
    //    a partially-occluded surface's transparency flag can't be recovered from the framebuffer.
    MaterialSurface unpackFramebuffer(uvec4 foregroundSampleRGBA, uvec4 backgroundSampleRGBA)
    {
        MaterialSurface ms;
        uvec2 foregroundSample = foregroundSampleRGBA.xy;
        uint backgroundSample = backgroundSampleRGBA.x;

        ms.foregroundShape = unpackShape(foregroundSample.x);
        ms.foregroundColor = unpackColor(foregroundSample.x);
        ms.foregroundDensity = unpackDensity(foregroundSample.y);
        ms.isTransparent = ((foregroundSample.y >> $(Int(DENSITY_BITS))) == 0) ? false : true;

        ms.backgroundColor = unpackColor(backgroundSample);
        ms.backgroundDensity = unpackDensity(backgroundSample >> $(Int(COLOR_BITS)));

        return ms;
    }

    #endif // FRAMEBUFFER_PACKING_H
"""


"UBO data for outputting to the foreground or background of a framebuffer"
GL.@std140 struct FrameBufferWriteData
    tex_foreground_depth::UInt64 # For foreground passes, this will be a dummy texture
                                 #    with max depth values
    foreground_mode::Bool # Whether we are writing to the foreground instead of background
end
const UBO_INDEX_FRAMEBUFFER_WRITE_DATA = 5
const UBO_NAME_FRAMEBUFFER_WRITE_DATA = "FrameBufferWriteData"
const UBO_CODE_FRAMEBUFFER_WRITE_DATA = """
    layout(std140, binding=$(UBO_INDEX_FRAMEBUFFER_WRITE_DATA-1)) uniform $UBO_NAME_FRAMEBUFFER_WRITE_DATA {
        $(glsl_decl(FrameBufferWriteData))
    } u_output;

    $SHADER_CODE_FRAMEBUFFER_PACKING

    out uvec4 fOut_packed;

    void writeFramebuffer(MaterialSurface surf) {
        //In background mode, we need to discard the front-most surface if it is transparent,
        //    so that partially-occluded surfaces can write to the background.
        uvec2 pixel = uvec2(gl_FragCoord.xy + 0.49999);
        bool isFrontmostSurface = (gl_FragCoord.z == texelFetch(sampler2D(u_output.tex_foreground_depth), ivec2(pixel), 0).r);
        if (!u_output.foreground_mode && surf.isTransparent && isFrontmostSurface)
            discard;

        //Pack the surface data appropriately.
        fOut_packed = uvec4(0, 0, 0, 0);
        if (u_output.foreground_mode)
            fOut_packed.xy = packForeground(surf);
        else
            fOut_packed.x = packBackground(surf, !isFrontmostSurface);
    }
"""


"UBO data for reading from a framebuffer"
GL.@std140 struct FrameBufferReadData
    tex_foreground::UInt64
    tex_background::UInt64
    char_grid_resolution::v2u # resolution of foreground and background textures
end
const UBO_INDEX_FRAMEBUFFER_READ_DATA = 2

const UBO_NAME_FRAMEBUFFER_READ_DATA = "FrameBufferReadData"
const UBO_CODE_FRAMEBUFFER_READ_DATA = """
    layout (std140, binding=$(UBO_INDEX_FRAMEBUFFER_READ_DATA-1)) uniform $UBO_NAME_FRAMEBUFFER_READ_DATA {
        $(glsl_decl(FrameBufferReadData))
    } u_framebuffer;

    $SHADER_CODE_FRAMEBUFFER_PACKING

    //Reads the surface data and calculates the ascii char UV
    //    at the given framebuffer UV coordinate.
    void readFramebuffer(vec2 uv, out MaterialSurface outSurface, out vec2 outCharUV)
    {
        outSurface = unpackFramebuffer(
            textureLod(usampler2D(u_framebuffer.tex_foreground), uv, 0.0),
            textureLod(usampler2D(u_framebuffer.tex_background), uv, 0.0)
        );

        vec2 charGridCellF = uv * u_framebuffer.char_grid_resolution;
        outCharUV = fract(charGridCellF);
    }
"""


"Helpers to write specific chars directly to the foreground"
const SHADER_CODE_DIRECT_CHAR_OUTPUT = """
    $UBO_CODE_FRAMEBUFFER_WRITE_DATA

    void writeChar_Letter(int letterIdx, bool uppercase,
                        inout MaterialSurface surface)
    {
        surface.foregroundShape = uppercase ? SHAPE_DIRECT_uppercase : SHAPE_DIRECT_lowercase;
        surface.foregroundDensity = calcDensityFloat(letterIdx, u_char_rendering.n_densities_per_shape[surface.foregroundShape]);
    }
    void writeChar_Digit(int digit, inout MaterialSurface surface)
    {
        surface.foregroundShape = SHAPE_DIRECT_digits;
        surface.foregroundDensity = calcDensityFloat(digit, u_char_rendering.n_densities_per_shape[surface.foregroundShape]);
    }
    void writeChar_Punctuation(int index, inout MaterialSurface surface)
    {
        surface.foregroundShape = SHAPE_DIRECT_punctuation;
        surface.foregroundDensity = calcDensityFloat(index, u_char_rendering.n_densities_per_shape[surface.foregroundShape]);
    }
"""
"Gets the density index for the given punctuation character, assuming it exists"
char_punctuation_idx(c::Char) = PUNCTUATION_DENSITY_INDICES[c]


@bp_enum(RenderPass,
    foreground,
    background
)