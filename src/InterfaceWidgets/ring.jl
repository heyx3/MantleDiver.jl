"Describes the chars to use in one loop of a Ring widget"
struct WidgetRingLayer
    edge_minX::CharDisplayValue
    edge_maxX::CharDisplayValue
    edge_minY::CharDisplayValue
    edge_maxY::CharDisplayValue

    corner_minX_minY::CharDisplayValue
    corner_maxX_minY::CharDisplayValue
    corner_minX_maxY::CharDisplayValue
    corner_maxX_maxY::CharDisplayValue

    #TODO: "Dropoff" values between the corner and the normal edges

    function WidgetRingLayer(fallback::CharDisplayValue = CharDisplayValue();
                             edges::CharDisplayValue = fallback,
                             corners::CharDisplayValue = fallback,
                             edges_horizontal::CharDisplayValue = edges,
                             edges_vertical::CharDisplayValue = edges,
                             edge_minX::CharDisplayValue = edges_vertical,
                             edge_maxX::CharDisplayValue = edges_vertical,
                             edge_minY::CharDisplayValue = edges_horizontal,
                             edge_maxY::CharDisplayValue = edges_horizontal,
                             corner_minX_minY::CharDisplayValue = corners,
                             corner_maxX_minY::CharDisplayValue = corners,
                             corner_minX_maxY::CharDisplayValue = corners,
                             corner_maxX_maxY::CharDisplayValue = corners)
        return new(edge_minX, edge_maxX, edge_minY, edge_maxY,
                   corner_minX_minY, corner_maxX_minY,
                   corner_minX_maxY, corner_maxX_maxY)
    end
end

"A ring of chars on the boundary of the panel"
struct WidgetRing <: AbstractWidget
    resolution::v2u
    layers::Vector{WidgetRingLayer} # From outside of panel to inside
end

function widget_init!(r::WidgetRing, panel::Panel)
    panel.space = Box2Di(
        min=one(v2i),
        size=r.resolution
    )

    function process(pixel::Vec2, value::CharDisplayValue)
        if exists(value.foreground)
            panel.foregrounds[pixel] = value.foreground
        end
        if exists(value.background)
            panel.backgrounds[pixel] = value.background
        end
    end

    for (layer_idx, layer_chars) in enumerate(r.layers)
        offset = layer_idx - 1
        corner_min = min_inclusive(panel.space) + offset
        corner_max = max_inclusive(panel.space) - offset
        corners = vappend(corner_min, corner_max)

        process(corners.xy, layer_chars.corner_minX_minY)
        process(corners.zy, layer_chars.corner_maxX_minY)
        process(corners.xw, layer_chars.corner_minX_maxY)
        process(corners.zw, layer_chars.corner_maxX_maxY)

        for x in (corner_min.x+1):(corner_max.x-1)
            process(v2i(x, corner_min.y), layer_chars.edge_minY)
            process(v2i(x, corner_max.y), layer_chars.edge_maxY)
        end
        for y in (corner_min.y+1):(corner_max.y-1)
            process(v2i(corner_min.x, y), layer_chars.edge_minX)
            process(v2i(corner_max.x, y), layer_chars.edge_maxX)
        end
    end
end