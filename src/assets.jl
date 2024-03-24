const ASSETS_FOLDER = "assets"

"Not including the space character which is implicitly at the min density of every shape"
const ASCII_CHARS_BY_SHAPE_THEN_DENSITY = tuple(
    # "Round" shape
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

    # "Wide" shape
    '-',
    '—', # \emdash
    '¬', # \neg
    '~',
    '∾', # \lazysinv
    '÷', # \div
    '±', # \pm
    '=',
    '≡', # \equiv
    '≣', # \Equiv

    # "Tall" shape
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

    # "Cross" shape
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

    # "Block" shape
    '⌷',
    'm',
    '░', # \blockqtrshaded
    '8',
    '▒', # \blockhalfshaded
    'M',
    '■', # \blacksquare
    '▓', # \blockthreeqtrshaded
    '█', # \blockfull


    # "Unusual" shape
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
)

# using FreeType, CSyntax
# FREETYPE_LIB::FT_Library = C_NULL

# "Loads all necessary assets from disk"
# mutable struct Assets
#     terminal_font::FT_Face
#     density_chars::Texture
# end

# function Assets()
#     global FREETYPE_LIB
#     window_size::v2i = get_window_size()

#     # Load FreeType.
#     @bp_check(FREETYPE_LIB == C_NULL, "Somebody else started FreeType??")
#     ft_error = @c FT_Init_FreeType(&FREETYPE_LIB)
#     @bp_check(ft_error == 0, "Error initializing FreeType: ", ft_error)

#     # Load the ASCII font.
#     terminal_face::FT_Face = C_NULL
#     @c FT_New_Face(
#         FREETYPE_LIB,
#         joinpath(ASSETS_FOLDER, "JetBrainsMono-Bold.ttf"),
#         0,
#         &terminal_face
#     )

# end

# function Base.close(a::Assets)
#     global FREETYPE_LIB
#     @c FT_Done_FreeType(&FREETYPE_LIB)
#     FREETYPE_LIB = C_NULL
# end
