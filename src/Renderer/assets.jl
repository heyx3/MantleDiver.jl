const ASSETS_FOLDER = "assets"

const FONT_NAME = "JetBrainsMono-Bold.ttf"


@bp_enum ShapeType(
    wide, tall,
    round, cross, block,
    unusual
)
"Not including the space character which is implicitly at the min density of every shape"
const ASCII_CHARS_BY_SHAPE_THEN_DENSITY = Dict(
    #NOTE: Set your editor to use the game font to preview these
    ShapeType.round => [
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
    ShapeType.wide => [
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
    ShapeType.tall => [
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
    ShapeType.cross => [
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
    ShapeType.block => [
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
    ShapeType.unusual => [
        '∘', # \circ
        '⋯', # \cdots
        '≗', # \circeq
        'a',
        'æ', # \ae
        '¢',
        'π', # \pi
        'Þ', # \TH
        '$',
        'ℵ', # \aleph
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

using FreeType, CSyntax
FREETYPE_LIB::FT_Library = C_NULL

"Loads all necessary assets from disk"
mutable struct Assets
    chars_font::FT_Face

    # Given a densit (X) and shape (Y), contains the min (RG) and max (BA) UV coordinates
    #    for the corresponding char in the font atlas.
    # Use point-clamp sampling (the texture's default).
    chars_atlas_lookup::Texture
    # Font atlas, single-channel, float sampling.
    # Look up the correct UV coordinates for each char from 'density_chars_lookup'.
    # Only one mip-level (i.e. mip-mapping is disabled).
    chars_atlas::Texture

    char_pixel_size::v2i
end

function Assets()
    # Collect all characters that need to be rendered.
    all_chars::Vector{Char} = unique(Iterators.flatten(values(ASCII_CHARS_BY_SHAPE_THEN_DENSITY)))
    push!(all_chars, ' ')
    push!(all_chars, ASCII_ERROR_CHAR)

    # Assign each char a part of the texture atlas.
    # For now, separate them horizontally with a small border.
    CHAR_PIXEL_SIZE::Int = 64
    BORDER_SIZE::Int = 1
    CHAR_ATLAS_SIZE = v2i(
        (CHAR_PIXEL_SIZE * length(all_chars)) +
          (BORDER_SIZE * (length(all_chars) - 1)),
        CHAR_PIXEL_SIZE
    )
    char_atlas_pixel_regions = Dict(
        c => Math.Box2Di(
            min = Math.v2i(1 + (CHAR_PIXEL_SIZE + 1) * i),
            size = CHAR_PIXEL_SIZE
        )
          for (i, c) in enumerate(all_chars)
    )
    char_atlas_uv_regions = Dict(
        c => Math.Box2Dd(
            min = (min_inclusive(bi) - 0.5) / convert(v2d, CHAR_ATLAS_SIZE),
            max = (max_inclusive(bi) - 0.5) / convert(v2d, CHAR_ATLAS_SIZE)
        )
          for (c, bi) in char_atlas_pixel_regions
    )

    # Build a matrix of char data, to build the density_chars_lookup.
    # Remember to put the space character behind each shape's list of ASCII chars!
    max_density = 1 + max(length.(values(ASCII_CHARS_BY_SHAPE_THEN_DENSITY)))
    n_shapes = length(ShapeType.instances())
    chars_atlas_lookup = Matrix{vRGBAf}(undef, n_shapes, max_density)
    for density in 1:max_density
        for shape in 1:n_shapes
            shape_enum = ShapeType.from(shape)
            by_density = ASCII_CHARS_BY_SHAPE_THEN_DENSITY[shape_enum]
            char = if density == 1
                ' '
            elseif density > length(by_density)+1
                ASCII_ERROR_CHAR
            else
                by_density[density - 1]
            end

            uv_rect = char_atlas_uv_regions[char]
            chars_atlas_lookup[shape, density] = vRGBAf(
                min_inclusive(uv_rect)...,
                max_inclusive(uv_rect)...
            )
        end
    end
    chars_atlas_lookup_tex = GL.Texture(
        GL.SimpleFormat(
            GL.FormatTypes.normalized_uint,
            GL.SimpleFormatComponents.RGBA,
            GL.SimpleFormatBitDepths.B16
        ),
        chars_atlas_lookup
        ;
        sampler = GL.TexSampler{2}(
            wrapping=GL.WrapModes.clamp,
            pixel_filter=GL.PixelFilters.rough
        ),
        n_mips = 1
    )

    # Load FreeType to render the font.
    global FREETYPE_LIB
    @bp_check(FREETYPE_LIB == C_NULL, "Somebody else started FreeType??")
    ft_error = @c FT_Init_FreeType(&FREETYPE_LIB)
    @bp_check(ft_error == 0, "Error initializing FreeType: ", ft_error)

    # Load the font face we're using.
    font_face::FT_Face = C_NULL
    font_path::String = joinpath(ASSETS_FOLDER, FONT_NAME)
    ft_error = @c FT_New_Face(
        FREETYPE_LIB,
        font_path,
        0,
        &font_face
    )
    @bp_check(ft_error == 0, "Error creating FreeType face from $font_path: $ft_error")
    ft_error = @c FT_Set_Pixel_Sizes(&font_face, CHAR_PIXEL_SIZE, CHAR_PIXEL_SIZE)
    @bp_check(ft_error == 0, "Error setting font face's pixel size to $CHAR_PIXEL_SIZE: $ft_error")

    # Render the chars into the atlas.
    #TODO: Upload as uint8 not float32, since that's what both FreeType and texture pixel format use.
    chars_atlas = fill(0.0f0, CHAR_ATLAS_SIZE...)
    for char in all_chars
        # Load the glyph in our font.
        char_glyph_idx = @c FT_Get_Char_Index(&font_face, char)
        ft_error = @c FT_Load_Glyph(&font_face, char_glyph_idx, 0)
        #NOTE: You should be allowed to pass FT_LOAD_RENDER to FT_Load_Glyph(),
        #    but in practice it doesn't work.
        @bp_check(ft_error == 0,
                  "Error loading/rendering char '$(escape_string(char))' (index $char_glyph_idx): $ft_error")

        # Render the glyph to a pixel array.
        glyph = unsafe_load(ft_face).glyph
        ft_error = FT_Render_Glyph(glyph, FT_RENDER_MODE_NORMAL)
        bitmap::FT_Bitmap = unsafe_load(glyph).bitmap
        @bp_check(bitmap.pixel_mode == FT_PIXEL_MODE_GRAY,
                  FT_Pixel_Mode(bitmap.pixel_mode))

        # Load the glyph into the texture atlas.
        byte_matrix = unsafe_wrap(Matrix{UInt8}, bitmap.buffer)
        pixel_region = char_atlas_pixel_regions[char]
        chars_atlas[pixel_region] = byte_matrix ./ @f32(255)
    end
    chars_atlas_tex = GL.Texture(
        GL.SimpleFormat(
            GL.FormatTypes.normalized_uint,
            GL.SimpleFormatComponents.R,
            GL.SimpleFormatBitDepths.B8
        ),
        chars_atlas
        ;
        sampler = GL.TexSampler{2}(
            wrapping=GL.WrapModes.clamp,
            pixel_filter=GL.PixelFilters.smooth
        ),
        n_mips = 1
    )

    return Assets(font_face, chars_atlas_lookup_tex, chars_atlas_tex, CHAR_PIXEL_SIZE)
end

function Base.close(a::Assets)
    close(a.chars_atlas_lookup)
    close(a.chars_atlas)

    @c FT_Done_Face(&a.chars_font)

    global FREETYPE_LIB
    @c FT_Done_FreeType(&FREETYPE_LIB)
    FREETYPE_LIB = C_NULL
end
