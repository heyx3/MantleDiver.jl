const DEBUG_ASSETS_FOLDER = "assets_debug"

"Assets that only exist in debug builds of the game"
mutable struct DebugAssets
    tex_button_play::Texture
    tex_button_pause::Texture
    tex_button_fast_forward::Texture
end
function Base.close(da::DebugAssets)
    for f in fieldnames(typeof(da))
        v = getfield(da, f)
        if v isa AbstractResource
            close(v)
        end
    end
end

function DebugAssets()
    function load_gui_tex(relative_path)::Texture
        pixels = FileIO.load(joinpath(DEBUG_ASSETS_FOLDER, relative_path))
        pixels = convert_pixel.(pixels', vRGBAu8)
        return GL.Texture(
            GL.SimpleFormat(
                GL.FormatTypes.normalized_uint,
                GL.SimpleFormatComponents.RGB,
                GL.SimpleFormatBitDepths.B8
            ),
            pixels
        )
    end

    return DebugAssets(
        load_gui_tex("playButton.png"),
        load_gui_tex("pauseButton.png"),
        load_gui_tex("fastForwardButton.png")
    )
end

