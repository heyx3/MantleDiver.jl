@bp_enum(CharShapeType,
    wide, tall,
    round, cross, block,
    unusual,

    # Special "shapes" that are used to directly write specific characters.
    DIRECT_lowercase,
    DIRECT_uppercase,
    DIRECT_digits,
    DIRECT_punctuation
)
const N_CHAR_SHAPES = length(CharShapeType.instances())
const DIRECT_CHAR_SHAPES = Set([
    CharShapeType.DIRECT_lowercase,
    CharShapeType.DIRECT_uppercase,
    CharShapeType.DIRECT_digits,
    CharShapeType.DIRECT_punctuation
])

"Not including the space character which is implicitly at the min density of every shape"
const ASCII_CHARS_BY_SHAPE_THEN_DENSITY = Dict(
    #NOTE: Preview the look of these by setting your editor to use the game font
    # Original font: "Iosevka SS16 Expanded"
    # Current game font: "JetBrains Mono"
    CharShapeType.round => [
        '.',
        # '•', # \bullet
        '¤',
        '®',
        # 'o',
        '○',
        # '*',
        '⊝', # \circledash
        # 'ø', # \o
        # '0',
        '@',
    ],
    CharShapeType.wide => [
        '-',
        '¬', # \neg
        # '~',
        '∾', # \lazysinv
        # '÷', # \div
        # '±', # \pm
        '=',
        # '≡', # \equiv
        '≣', # \Equiv
    ],
    CharShapeType.tall => [
        ':',
        # ';',
        '¦', # \brokenbar
        # 'i',
        'j',
        # '!',
        '|',
        # '1',
        '‡', # \ddagger
        'I',
        '¶',
        '║',
    ],
    CharShapeType.cross => [
        '›', # \guilsinglright
        # '»',
        '×', # \times
        # '+',
        # 'x',
        '¼',
        'X',
        # 'Ž', # Z\check
        '%',
        '#',
    ],
    CharShapeType.block => [
        '⌷',
        '�',
        '░', # \blockqtrshaded
        '▒', # \blockhalfshaded
        # '■', # \blacksquare
        '▓', # \blockthreeqtrshaded
        '█', # \blockfull
    ],
    CharShapeType.unusual => [
        # '∘', # \circ
        # '⋯', # \cdots
        'æ', # \ae
        '≗', # \circeq
        '¢',
        # 'a',
        # 'π', # \pi
        'Þ', # \TH
        # '$',
        # 'ℵ', # \aleph  not supported in this font :(
        '§', # \S
        # '€', # \euro
        # 'ß', # \ss
        # '&',
        # 'G',
        'Ä', # A\ddot
    ],

    CharShapeType.DIRECT_lowercase => collect('a':'z'),
    CharShapeType.DIRECT_uppercase => collect('A':'Z'),
    CharShapeType.DIRECT_digits => collect('0':'9'),
    CharShapeType.DIRECT_punctuation => [
        ',', ';', '\'', '"', '-', '_', '+', '=',
        '!', '@', '#', '$', '%', '^', '&', '*', '(', ')',
        '.', '?', '/', '\\',
        '<', '>', '[', ']', '{', '}',
        '`', '~', '|'
    ]
)
function get_char_by_density(group::E_CharShapeType, density::Float32)
    raw_idx = 1 + round(Int, density * length(group))
    return group[clamp(raw_idx, 1, length(group))]
end

"Maps each punctuation character to its index in the `DIRECT_punctuation` char shape"
const PUNCTUATION_DENSITY_INDICES = Dict(
    c => i for (i, c) in enumerate(ASCII_CHARS_BY_SHAPE_THEN_DENSITY[CharShapeType.DIRECT_punctuation])
)

# Define the precise mapping between density float and density index.
# All using 0-based math for shader purposes!
const SHADER_CALC_DENSITY_INDEX = """
    #ifndef CALC_DENSITY_INDEX_H
    #define CALC_DENSITY_INDEX_H

    uint calcDensityIndex(float densityF, uint densityMaxExclusive)
    {
        uint u = uint(densityF * (densityMaxExclusive - uint(1)));
        return clamp(u, uint(0), densityMaxExclusive - uint(1));
    }
    float calcDensityFloat(int densityI, uint nIndices)
    {
        return clamp(float(densityI) / float(nIndices - 1), 0.0, 1.0);
    }

    $(map(CharShapeType.instances()) do shape
        return """#define SHAPE_$shape $(Int(shape))
    """ end...)

    #endif // CALC_DENSITY_INDEX_H
"""
calc_density_float(zero_based_idx, n_indices) = saturate(@f32(
    (zero_based_idx + 0.5) / (n_indices)
))


"An unpacked CPU representation of a framebuffer foreground pixel"
struct CharForegroundValue
    color::UInt8
    shape::E_CharShapeType
    density::Float32
    is_transparent::Bool
end
"An unpacked CPU representation of a framebuffer background pixel"
struct CharBackgroundValue
    color::UInt8
    density::Float32
end

"An unpacked representation of an optional foreground and/or background pixel"
@kwdef struct CharDisplayValue
    foreground::Optional{CharForegroundValue} = nothing
    background::Optional{CharBackgroundValue} = nothing
end

"Gets the shape and density needed to represent the given character"
function CharForegroundValue(c::Char, color = one(UInt8), is_transparent::Bool = false)::CharForegroundValue
    if isletter(c)
        if isuppercase(c)
            return CharForegroundValue(
                convert(UInt8, color),
                CharShapeType.DIRECT_uppercase,
                calc_density_float(c - 'A', 26),
                is_transparent
            )
        else
            return CharForegroundValue(
                convert(UInt8, color),
                CharShapeType.DIRECT_lowercase,
                calc_density_float(c - 'a', 26),
                is_transparent
            )
        end
    elseif isdigit(c)
        CharForegroundValue(
            convert(UInt8, color),
            CharShapeType.DIRECT_digits,
            calc_density_float(c - '0', 10),
            is_transparent
        )
    elseif haskey(PUNCTUATION_DENSITY_INDICES, c)
        return CharForegroundValue(
            convert(UInt8, color),
            CharShapeType.DIRECT_punctuation,
            calc_density_float(PUNCTUATION_DENSITY_INDICES[c] - 1,
                               length(PUNCTUATION_DENSITY_INDICES)),
            is_transparent
        )
    elseif c == ' '
        return CharForegroundValue(
            convert(UInt8, color),
            CharShapeType.wide,
            zero(Float32),
            is_transparent
        )
    else
        error("Unsupported char: '", c, "' (", Int(c), " / ", UInt(c), ")")
    end
end

#TODO: Packing functions for Char[Foreground|Background]Value


"
A fallback when an invalid character is rendered.
Should be different from any characters in other shapes (not including the `DIRECT_` ones).
"
const ASCII_ERROR_CHAR = '?'
for shape in CharShapeType.instances()
    if !in(shape, DIRECT_CHAR_SHAPES)
        if ASCII_ERROR_CHAR in ASCII_CHARS_BY_SHAPE_THEN_DENSITY[shape]
            error("\"Error\" char is used as a normal char, in shape ", shape)
        end
    end
end


"UBO representation of the data for rendering chars"
GL.@std140 struct CharRenderAssetBuffer
    tex_uv_lookup::UInt64
    tex_atlas::UInt64
    tex_palette::UInt64
    n_colors::UInt32
    n_shapes::UInt32
    n_densities_per_shape::StaticBlockArray{N_CHAR_SHAPES, UInt32} # inclusive, 0-bassed
end
const UBO_INDEX_CHAR_RENDERING = 1

const UBO_NAME_CHAR_RENDERING = "CharRenderAssetBuffer"
const UBO_CODE_CHAR_RENDERING = """
    #ifndef UBO_CHAR_RENDERING_HEADER
    #define UBO_CHAR_RENDERING_HEADER

    layout (std140, binding=$(UBO_INDEX_CHAR_RENDERING-1)) uniform $UBO_NAME_CHAR_RENDERING {
        $(glsl_decl(CharRenderAssetBuffer))
    } u_char_rendering;

    $SHADER_CALC_DENSITY_INDEX

    //Gets the UV rectangle (min=XY, max=ZW)
    //    for a particular character in the texture atlas, given its shape and density.
    vec4 charAtlasMinMaxUV(uint shape, float density) {
        shape = clamp(shape, uint(0), uint(u_char_rendering.n_shapes - 1));
        density = clamp(density, 0.0, 1.0);

        uint densityU = calcDensityIndex(
            density,
            u_char_rendering.n_densities_per_shape[shape]
        );

        return texelFetch(sampler2D(u_char_rendering.tex_uv_lookup), ivec2(densityU, shape), 0);
    }

    //Gets the rendered greyscale font character, at the given UV,
    //    using the given shape and density values to select a char.
    float readChar(uint shape, float density, vec2 uv) {
        vec4 uvRect = charAtlasMinMaxUV(shape, density);
        return textureLod(sampler2D(u_char_rendering.tex_atlas),
                          mix(uvRect.xy, uvRect.zw, uv),
                          0.0).r;
    }

    //Gets a paletted color value.
    vec3 readColor(uint color) {
        return texelFetch(sampler2D(u_char_rendering.tex_palette),
                          ivec2(clamp(color, uint(0), uint(u_char_rendering.n_colors - 1)),
                                0),
                          0).rgb;
    }

    #endif //Header guard
"""