@bp_enum(CharShapeType,
    wide, tall,
    round, cross, block,
    unusual
)
const N_CHAR_SHAPES = length(CharShapeType.instances())

"Not including the space character which is implicitly at the min density of every shape"
const ASCII_CHARS_BY_SHAPE_THEN_DENSITY = Dict(
    #NOTE: Preview the look of these by setting your editor to use the game font
    CharShapeType.round => [
        '•', # \bullet
        '¤',
        'o',
        '○',
        '*',
        '®',
        'ø', # \o
        '⊝', # \circledash
        '0',
        '@',
    ],
    CharShapeType.wide => [
        '-',
        '¬', # \neg
        '~',
        '∾', # \lazysinv
        '÷', # \div
        '±', # \pm
        '=',
        '≡', # \equiv
        '≣', # \Equiv
    ],
    CharShapeType.tall => [
        ':',
        ';',
        '¦', # \brokenbar
        'i',
        'j',
        '!',
        '|',
        '1',
        'I',
        '¶',
        '║',
    ],
    CharShapeType.cross => [
        '›', # \guilsinglright
        '»',
        '×', # \times
        '+',
        'x',
        '‡', # \ddagger
        'X',
        '¼',
        'Ž', # Z\check
        '%',
        '#', 
        '�',
    ],
    CharShapeType.block => [
        '⌷',
        'm',
        '░', # \blockqtrshaded
        '8',
        '▒', # \blockhalfshaded
        'M',
        '■', # \blacksquare
        '▓', # \blockthreeqtrshaded
        '█', # \blockfull
    ],
    CharShapeType.unusual => [
        '∘', # \circ
        '⋯', # \cdots
        '≗', # \circeq
        'a',
        'æ', # \ae
        '¢',
        'π', # \pi
        'Þ', # \TH
        '$',
        # 'ℵ', # \aleph  not supported in this font :(
        '§', # \S
        '€', # \euro
        'ß', # \ss
        '&',
        'G',
        'Ä', # A\ddot
    ],
)
"A fallback when an invalid character is rendered. Should not match any other character."
const ASCII_ERROR_CHAR = '?'
@bp_check(none(v -> v == ASCII_ERROR_CHAR,
               Iterators.flatten(values(ASCII_CHARS_BY_SHAPE_THEN_DENSITY))),
          "Error char is used as a normal char: '", ASCII_ERROR_CHAR, "'")

"UBO representation of the data for rendering chars"
GL.@std140 struct CharRenderAssetBuffer
    tex_uv_lookup::UInt64
    tex_atlas::UInt64
    tex_palette::UInt64
    n_colors::UInt32
    n_shapes::UInt32
    n_densities_per_shape::StaticBlockArray{N_CHAR_SHAPES, UInt32} # inclusive, 0-bassed
    #TODO: Provide some weighting functions for each char shape -- exponent curve, relative importance of min and max density
end
const UBO_INDEX_CHAR_RENDERING = 1

const UBO_NAME_CHAR_RENDERING = "CharRenderAssetBuffer"
const UBO_CODE_CHAR_RENDERING = """
layout (std140, binding=$(UBO_INDEX_CHAR_RENDERING-1)) uniform $UBO_NAME_CHAR_RENDERING {
    $(glsl_decl(CharRenderAssetBuffer))
} u_char_rendering;

//Gets the UV rectangle (min=XY, max=ZW)
//    for a particular character in the texture atlas, given its shape and density.
vec4 charAtlasMinMaxUV(uint shape, float density) {
    shape = clamp(shape, uint(0), uint(u_char_rendering.n_shapes - 1));
    density = clamp(density, 0, 1);

    uint maxDensity = u_char_rendering.n_densities_per_shape[shape] - 1;
    uint densityU = clamp(uint(density * maxDensity),
                          uint(0), uint(maxDensity));

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
"""