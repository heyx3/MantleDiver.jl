"Some kind of image (represented as a grid of chars)"
struct WidgetImage <: AbstractWidget
    pixels::Matrix{Tuple{Optional{CharForegroundValue}, Optional{CharBackgroundValue}}}
end

function widget_init!(img::WidgetImage, panel::Panel)
    for (x,y) in Iterators.product(axes(img.pixels)...)
        (foreground, background) = img.pixels
        exists(foreground) && (panel.foregrounds[v2i(x, y)] = foreground)
        exists(background) && (panel.backgrounds[v2i(x, y)] = background)
    end
    return nothing
end