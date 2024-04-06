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
const SHADER_CODE_FRAMEBUFFER_DATA = """
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

uvec2 packForeground(MaterialSurface surf)
{
    return uvec2(
        packShape(surf.foregroundShape) |
            packShape(surf.foregroundColor),
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
"""


"UBO data buffer for a single framebuffer"
GL.@std140 struct FrameBufferData
    tex_foreground::UInt64
    tex_background::UInt64
    char_grid_resolution::v2u # resolution of foreground and background textures
end
const UBO_INDEX_FRAMEBUFFER_DATA = 2

const UBO_NAME_FRAMEBUFFER_DATA = "FrameBufferData"
const UBO_CODE_FRAMEBUFFER_DATA = """
layout (std140, binding=$(UBO_INDEX_FRAMEBUFFER_DATA-1)) uniform $UBO_NAME_FRAMEBUFFER_DATA {
    usampler2D texForeground;
    usampler2D texBackground;
    uvec2 charGridResolution;
} u_framebuffer;

//Reads the surface data and calculates the ascii char UV
//    at the given framebuffer UV coordinate.
void readFramebuffer(vec2 uv, out MaterialSurface outSurface, out vec2 outCharUV)
{
    outSurface = unpackFramebuffer(
        textureLod(u_framebuffer.texForeground, uv, 0.0),
        textureLod(u_framebuffer.texBackground, uv, 0.0)
    );

    vec2 charGridCellF = uv * u_framebuffer.charGridResolution;
    outCharUV = fract(charGridCellF);
}
"""