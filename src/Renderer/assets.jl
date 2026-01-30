const ASSETS_FOLDER = "assets"

const FILE_NAME_FONT = "JetBrainsMono-Bold.ttf"
const FILE_NAME_PALETTE = "Palette.png"

const CHAR_PIXEL_SIZE = 16


Bplus.@bp_enum(FramebufferRenderMode,
    regular,
    char_greyscale,
    foreground_shape,
    foreground_color,
    foreground_density,
    background_color,
    background_density,
    is_foreground_transparent
)
const UNIFORM_NAME_RENDER_MODE = "u_outputMode";


"Loads all necessary assets from disk"
mutable struct Assets
    ft_lib::FT_Library
    chars_font::FT_Face

    # Given a density (X) and shape (Y), contains the min (RG) and max (BA) UV coordinates
    #    for the corresponding char in the font atlas.
    # Use point-clamp sampling (the texture's default).
    chars_atlas_lookup::Texture
    # Font atlas, single-channel, float sampling.
    # Look up the correct UV coordinates for each char from 'density_chars_lookup'.
    # Only one mip-level (i.e. mip-mapping is disabled).
    chars_atlas::Texture
    char_pixel_size::v2i

    palette::Texture

    shader_render_chars::Program
    shader_render_bloom::Program
    shader_render_segmentations_line::Program
    shader_render_segmentations_corner::Program
    shader_render_interface_foreground::Program
    shader_render_interface_background::Program

    chars_ubo_data::CharRenderAssetBuffer
    chars_ubo::GL.Buffer

    shader_bloom_blur::Program

    # A tiny depth texture, cleared to max depth.
    blank_depth_tex::Texture

    segmentation::SegmentationAssets
end

function Assets()
    # Collect all characters that need to be rendered.
    all_chars::Vector{Char} = unique(Iterators.flatten(values(ASCII_CHARS_BY_SHAPE_THEN_DENSITY)))
    push!(all_chars, ' ')
    push!(all_chars, ASCII_ERROR_CHAR)

    # Assign each char a part of the texture atlas.
    # For now, separate them horizontally with a small border.
    BORDER_SIZE::Int = 1
    CHAR_ATLAS_SIZE = v2i(
        (CHAR_PIXEL_SIZE * length(all_chars)) +
          (BORDER_SIZE * (length(all_chars) - 1)),
        CHAR_PIXEL_SIZE
    )
    char_atlas_pixel_regions = Dict(
        c => Math.Box2Di(
            min = Math.v2i(1 + ((CHAR_PIXEL_SIZE + 1) * (i - 1)), 1),
            size = Math.v2i(CHAR_PIXEL_SIZE, CHAR_PIXEL_SIZE)
        )
          for (i, c) in enumerate(all_chars)
    )
    char_atlas_uv_regions = Dict(
        c => Math.Box2Dd(
            min = (min_inclusive(bi) - 1.0) / convert(v2d, CHAR_ATLAS_SIZE),
            max = (max_inclusive(bi)) / convert(v2d, CHAR_ATLAS_SIZE)
        )
          for (c, bi) in char_atlas_pixel_regions
    )

    # Build a matrix of char data, to build the density_chars_lookup.
    # Remember to put the space character behind each non-direct shape.
    max_density = 1 + maximum(length.(values(ASCII_CHARS_BY_SHAPE_THEN_DENSITY)))
    n_shapes = length(CharShapeType.instances())
    chars_atlas_lookup = Matrix{vRGBAf}(undef, max_density, n_shapes)
    for shape in 1:n_shapes
        shape_enum = CharShapeType.from(shape - 1)
        shape_is_direct = shape_enum in DIRECT_CHAR_SHAPES
        by_density = ASCII_CHARS_BY_SHAPE_THEN_DENSITY[shape_enum]
        for density in 1:max_density
            index_offset = (shape_is_direct ? 0 : 1)
            char::Char = if !shape_is_direct && (density == 1)
                ' '
            elseif density > length(by_density) + index_offset
                ASCII_ERROR_CHAR
            else
                by_density[density - index_offset]
            end

            uv_rect = char_atlas_uv_regions[char]
            chars_atlas_lookup[density, shape] = vRGBAf(
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
    ft_lib::FT_Library = C_NULL
    ft_error = @c FT_Init_FreeType(&ft_lib)
    @bp_check(ft_error == 0, "Error initializing FreeType: ", ft_error)

    # Load the font face we're using.
    font_face::FT_Face = C_NULL
    font_path::String = joinpath(ASSETS_FOLDER, FILE_NAME_FONT)
    ft_error = @c FT_New_Face(
        ft_lib,
        font_path,
        0,
        &font_face
    )
    @bp_check(ft_error == 0, "Error creating FreeType face from $font_path: $ft_error")
    ft_error = @c FT_Set_Pixel_Sizes(font_face, CHAR_PIXEL_SIZE, CHAR_PIXEL_SIZE)
    @bp_check(ft_error == 0, "Error setting font face's pixel size to $CHAR_PIXEL_SIZE: $ft_error")

    # Render the chars into the atlas.
    #TODO: Upload as uint8 not float32, since that's what both FreeType and texture pixel format use.
    chars_atlas = fill(0.0f0, CHAR_ATLAS_SIZE...)
    for char in all_chars
        # Load the glyph in our font.
        char_glyph_idx = @c FT_Get_Char_Index(font_face, char)
        ft_error = @c FT_Load_Glyph(font_face, char_glyph_idx, 0)
        #NOTE: You should be allowed to pass FT_LOAD_RENDER to FT_Load_Glyph(),
        #    but in practice it doesn't work.
        @bp_check(ft_error == 0,
                  "Error loading/rendering char '$(escape_string(char))' (index $char_glyph_idx): ",
                    ft_error)

        # Render the glyph to a pixel array.
        glyph = unsafe_load(font_face).glyph
        ft_error = FT_Render_Glyph(glyph, FT_RENDER_MODE_NORMAL)
        bitmap::FT_Bitmap = unsafe_load(glyph).bitmap
        @bp_check(bitmap.pixel_mode == FT_PIXEL_MODE_GRAY,
                  FT_Pixel_Mode(bitmap.pixel_mode))
        byte_matrix = Matrix{UInt8}(undef, bitmap.rows, bitmap.width)
        for row_i in 1:bitmap.rows
            byte_matrix[row_i, :] = unsafe_wrap(
                Vector{UInt8},
                bitmap.buffer + (bitmap.pitch * (row_i-1)),
                bitmap.width
            )
        end

        # FreeType doesn't guarantee that glyph bitmaps will exactly match the requested pixel size.
        # Chop off excess pixels and fill in the missing ones.
        for axis in 1:2
            missing_lines = CHAR_PIXEL_SIZE - size(byte_matrix, axis)
            missing_half = abs(missing_lines) ÷ 2
            # If missing an odd number of pixel rows/columns,
            #    we will randomly place an extra row/column at the beginning or end of the matrix.
            missing_extra_line::Optional{Bool} = if isodd(missing_lines)
                rand(Utilities.PRNG(0x234b, Int64(char)), Bool)
            else
                nothing
            end

            if missing_lines < 0 # Too many pixels
                missing_lines = -missing_lines

                min_side_offset = (missing_extra_line === true  ? 1 : 0)
                max_side_offset = (missing_extra_line === false ? 1 : 0)
                slice_start = missing_half + min_side_offset + 1
                slice_end = size(byte_matrix, axis) - missing_half - max_side_offset
                byte_matrix = selectdim(byte_matrix, axis, slice_start:slice_end)
            elseif missing_lines > 0 # Too few pixels
                missing_size = tuple(
                    (axis == 1) ? missing_half : size(byte_matrix, 1),
                    (axis == 2) ? missing_half : size(byte_matrix, 2)
                )
                missing_data = fill(0x00, missing_size...)
                byte_matrix = cat(missing_data, byte_matrix, missing_data; dims=axis)

                # If there's one extra line to place, randomly add it
                #    to one of the two ends of the pixel matrix.
                if exists(missing_extra_line)
                    missing_size = tuple(
                        (axis == 1) ? 1 : size(byte_matrix, 1),
                        (axis == 2) ? 1 : size(byte_matrix, 2)
                    )
                    missing_data = fill(0x00, missing_size...)
                    if missing_extra_line
                        byte_matrix = cat(missing_data, byte_matrix; dims=axis)
                    else
                        byte_matrix = cat(byte_matrix, missing_data; dims=axis)
                    end
                end
            end
        end
        @bp_check(vsize(byte_matrix, true_order=true) == Vec(CHAR_PIXEL_SIZE, CHAR_PIXEL_SIZE),
                    vsize(byte_matrix, true_order=true))

        # Load the glyph into the texture atlas.
        # The axes need to be flipped for upload.
        byte_matrix = byte_matrix'
        byte_matrix = byte_matrix[1:end, end:-1:1] # Flip Y
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

    palette = FileIO.load(joinpath(ASSETS_FOLDER, FILE_NAME_PALETTE))
    palette = convert_pixel.(palette', vRGBu8)
    palette_resolution::v2i = vsize(palette)
    @d8_assert(palette_resolution.y == 1,
               "Palette should be Nx1 resolution, got ", palette_resolution)
    n_colors::Int = palette_resolution.x
    palette_tex = GL.Texture(
        GL.SimpleFormat(
            GL.FormatTypes.normalized_uint,
            GL.SimpleFormatComponents.RGB,
            GL.SimpleFormatBitDepths.B8
        ),
        palette
        ;
        sampler = GL.TexSampler{2}(
            wrapping=GL.WrapModes.clamp,
            pixel_filter=GL.PixelFilters.rough
        )
    )

    shader_render_chars = Bplus.GL.bp_glsl_str("""
        #START_VERTEX
            $(make_vertex_shader_blit())

        #START_FRAGMENT
            in vec2 vOut_uv;
            out vec4 fOut_color;
            out vec4 fOut_bloomInit;

            $UBO_CODE_FRAMEBUFFER_READ_DATA
            $UBO_CODE_CHAR_RENDERING

            uniform int $UNIFORM_NAME_RENDER_MODE;

            $SHADER_CODE_UTILS

            void main() {
                //Read data from the framebuffer.
                MaterialSurface surface;
                vec2 charUV;
                readFramebuffer(vOut_uv, surface, charUV);

                //Look up the intended color for the char.
                vec3 foregroundColor = readColor(surface.foregroundColor);
                vec3 backgroundColor = readColor(surface.backgroundColor) *
                                         surface.backgroundDensity;
                float charA = readChar(surface.foregroundShape, surface.foregroundDensity, charUV);

                fOut_color = vec4(1, 0, 1, 1);
                fOut_bloomInit = vec4(foregroundColor * charA * surface.foregroundShine, 1);

                //Decide what to actually output, based on the rendering mode.
                #define PICK_OUTPUT(colorRGB) { \
                    fOut_color.rgb = vec3(colorRGB); \
                    return; \
                }
                if ($UNIFORM_NAME_RENDER_MODE == $(Int(FramebufferRenderMode.regular)))
                    PICK_OUTPUT(mix(backgroundColor, foregroundColor, charA))
                else if ($UNIFORM_NAME_RENDER_MODE == $(Int(FramebufferRenderMode.foreground_shape)))
                    PICK_OUTPUT(PROCEDURAL_GRADIENT(
                        float(surface.foregroundShape) / $N_CHAR_SHAPES,
                        0.5, 0.5, vec3(1.4, 1.7, 2.4), vec3(0.3, 0.2, 0.2)
                    ))
                else if ($UNIFORM_NAME_RENDER_MODE == $(Int(FramebufferRenderMode.foreground_color)))
                    PICK_OUTPUT(float(surface.foregroundColor) / float(u_char_rendering.n_colors - 1))
                else if ($UNIFORM_NAME_RENDER_MODE == $(Int(FramebufferRenderMode.foreground_density)))
                    PICK_OUTPUT(surface.foregroundDensity)
                else if ($UNIFORM_NAME_RENDER_MODE == $(Int(FramebufferRenderMode.background_color)))
                    PICK_OUTPUT(float(surface.backgroundColor / float(u_char_rendering.n_colors - 1)))
                else if ($UNIFORM_NAME_RENDER_MODE == $(Int(FramebufferRenderMode.background_density)))
                    PICK_OUTPUT(surface.backgroundDensity)
                else if ($UNIFORM_NAME_RENDER_MODE == $(Int(FramebufferRenderMode.is_foreground_transparent)))
                    PICK_OUTPUT(surface.isTransparent ? 1.0 : 0.0)
                else if ($UNIFORM_NAME_RENDER_MODE == $(Int(FramebufferRenderMode.char_greyscale)))
                    PICK_OUTPUT(charA)
            }
    """)

    shader_render_bloom = Bplus.GL.bp_glsl_str("""
        #START_VERTEX
            $(make_vertex_shader_blit())

        #START_FRAGMENT

            in vec2 vOut_uv;
            out vec4 fOut_bloomAdd;

            uniform sampler2D u_bloomRaw;
            uniform float u_bloomStrength;

            void main() {
                fOut_bloomAdd = clamp(
                    u_bloomStrength * textureLod(u_bloomRaw, vOut_uv, 0),
                    0.0, 1.0
                );
                fOut_bloomAdd.a = 1;
            }
    """)

    chars_ubo_data = CharRenderAssetBuffer(
        GL.get_ogl_handle(GL.get_view(chars_atlas_lookup_tex)),
        GL.get_ogl_handle(GL.get_view(chars_atlas_tex)),
        GL.get_ogl_handle(GL.get_view(palette_tex)),
        n_colors,
        n_shapes,
        ntuple(Val(N_CHAR_SHAPES)) do shape_i
            shape = CharShapeType.from(shape_i - 1)
            return length(ASCII_CHARS_BY_SHAPE_THEN_DENSITY[shape]) + 1
        end
    )
    chars_ubo = GL.Buffer(false, chars_ubo_data)
    GL.set_uniform_block(chars_ubo, UBO_INDEX_CHAR_RENDERING)

    shader_bloom_blur = Bplus.GL.bp_glsl_str("""
        #START_VERTEX
            $(make_vertex_shader_blit())

        #START_FRAGMENT
            in vec2 vOut_uv;
            out vec4 fOut_color;

            $UBO_CODE_BLUR_KERNEL

            uniform sampler2D u_sourceTex;
            uniform vec2 u_destTexel;
            uniform float u_blurSpreadScale;

            void main() {
                fOut_color = vec4(0, 0, 0, 1);
                for (int i = 0; i < u_blur_kernel.n_samples; ++i)
                {
                    vec2 uv = vOut_uv + (u_blur_kernel.samples[i].dest_pixel_offset *
                                          u_blurSpreadScale * u_destTexel);
                    fOut_color.rgb += u_blur_kernel.samples[i].weight *
                                      textureLod(u_sourceTex, uv, 0).rgb;
                }

                fOut_color.a = 1;
            }
    """)

    return Assets(ft_lib, font_face,
                  chars_atlas_lookup_tex, chars_atlas_tex,
                  v2i(CHAR_PIXEL_SIZE, CHAR_PIXEL_SIZE),
                  palette_tex,
                  shader_render_chars, shader_render_bloom,
                  GL.bp_glsl_str(SHADER_RENDER_SEGMENTATION_LINES),
                  GL.bp_glsl_str(SHADER_RENDER_SEGMENTATION_LINES),
                  GL.bp_glsl_str("#define RENDER_FOREGROUND \n $SHADER_CODE_RENDER_INTERFACE"),
                  GL.bp_glsl_str("#define RENDER_BACKGROUND \n $SHADER_CODE_RENDER_INTERFACE"),
                  chars_ubo_data, chars_ubo,
                  shader_bloom_blur,
                  GL.Texture(GL.DepthStencilFormats.depth_16u,
                             [ @f32(1) ;; ],
                             sampler = TexSampler{2}(
                                pixel_filter = PixelFilters.rough
                             )),
                  SegmentationAssets())
end

function Base.close(a::Assets)
    close(a.segmentation)
    close(a.chars_atlas_lookup)
    close(a.chars_atlas)
    close(a.palette)
    close(a.shader_render_chars)
    close(a.shader_render_bloom)
    close(a.chars_ubo)
    close(a.blank_depth_tex)
    close(a.shader_render_segmentations_corner)
    close(a.shader_render_segmentations_line)
    close(a.shader_render_interface_foreground)
    close(a.shader_render_interface_background)
    close(a.shader_bloom_blur)

    @c FT_Done_Face(a.chars_font)
    @c FT_Done_FreeType(a.ft_lib)
end
