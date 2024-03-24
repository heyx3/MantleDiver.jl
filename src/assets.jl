const ASSETS_FOLDER = "assets"


@bp_enum ShapeTypes round wide tall cross block unusual

"Not including the space character which is implicitly at the min density of every shape"
const ASCII_CHARS_BY_SHAPE_THEN_DENSITY = Dict(
    ShapeTypes.round => [
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
    ShapeTypes.wide => [
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
    ShapeTypes.tall => [
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
    ShapeTypes.cross => [
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
    ShapeTypes.block => [
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
    ShapeTypes.unusual => [
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
    ]
)

using FreeType, CSyntax
FREETYPE_LIB::FT_Library = C_NULL

"Loads all necessary assets from disk"
mutable struct Assets
    terminal_font::FT_Face
    density_chars::Texture
end

function Assets()
    global FREETYPE_LIB
    window_size::v2i = get_window_size()

    # Load FreeType.
    @bp_check(FREETYPE_LIB == C_NULL, "Somebody else started FreeType??")
    ft_error = @c FT_Init_FreeType(&FREETYPE_LIB)
    @bp_check(ft_error == 0, "Error initializing FreeType: ", ft_error)

    # Load the ASCII font.
    terminal_face::FT_Face = C_NULL
    @c FT_New_Face(
        FREETYPE_LIB,
        joinpath(ASSETS_FOLDER, "JetBrainsMono-Bold.ttf"),
        0,
        &terminal_face
    )

end

function Base.close(a::Assets)
    global FREETYPE_LIB
    @c FT_Done_FreeType(&FREETYPE_LIB)
    FREETYPE_LIB = C_NULL
end
