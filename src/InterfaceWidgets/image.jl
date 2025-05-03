"Some kind of image (represented as a grid of chars)"
struct WidgetImage <: AbstractWidget
    pixels::Matrix{Tuple{Optional{CharForegroundValue}, Optional{CharBackgroundValue}}}
    parent_offset::v2i

    WidgetImage(pixels, parent_offset = zero(v2i)) = new(pixels, parent_offset)
end

function widget_init!(img::WidgetImage, panel::Panel)
    panel.space = Box2Di(
        min=img.parent_offset,
        size=vsize(pixels)
    )
    for (x,y) in Iterators.product(axes(img.pixels)...)
        (foreground, background) = img.pixels
        exists(foreground) && (panel.foregrounds[v2i(x, y)] = foreground)
        exists(background) && (panel.backgrounds[v2i(x, y)] = background)
    end
    return nothing
end