
sanitize_widget_text(s::AbstractString) = replace(string(s), "\n\r"=>"\n", "\r\n"=>"\n", "\r"=>"\n")

@bp_enum(TextAlignment,
    min, # Left/top
    centered,
    max, # Right/bottom

    # Centered, and biased towards the left/top if there's an even number of spaces.
    centered_bias_min,
    # Centered, and biased towards the right/bottom if there's an even number of spaces.
    centered_bias_max,
)
"
Finds the space covered by a widget; given its alignment, anchor pos, and total size.
Operates on a single component.
"
function widget_anchored_space(alignment::E_TextAlignment, anchor_pos::Integer, size::Integer)::Interval
    return convert(Interval{promote_type(typeof(anchor_pos), typeof(size))},
        if alignment == TextAlignment.min
            Interval(min=anchor_pos, size=size)
        elseif alignment == TextAlignment.max
            Interval(max=anchor_pos, size=size)
        elseif alignment in (TextAlignment.centered, TextAlignment.centered_bias_max)
            Interval(@ano_value(Int), center=anchor_pos, size=size)
        elseif alignment == TextAlignment.centered_bias_min
            Interval(@ano_value(Int), center=(anchor_pos - (iseven(size) ? 1 : 0)), size=size)
        else
            error("Unhandled: ", alignment)
        end
    )
end

"
Some text. Supports line-breaks.
Anchored based on its alignment, for example
  min horzontal and centered vertical means the anchor point is at the min X cell and middle Y cell.
"
@kwdef struct WidgetText <: AbstractWidget
    text::String
    color::UInt8
    anchor_point::v2i
    background::Optional{CharBackgroundValue} = CharBackgroundValue(
        0, 0.0
    )
    background_covers_whole_space::Bool = true # If true, then it covers the entire rectangular bounds of the label.
                                               # If false, then it skips grid cells outside the text
                                               #   (though spaces within the text are still covered).
    horizontal_alignment::E_TextAlignment = TextAlignment.min
    vertical_alignment::E_TextAlignment = TextAlignment.centered
end
WidgetText(text, anchor_point, color; kw...) = WidgetText(;
    text=sanitize_widget_text(text),
    color=convert(UInt8, color),
    anchor_point=convert(v2i, anchor_point),
    kw...
)

function widget_init!(w_text::WidgetText, panel::Panel)
    separator_idcs = findall('\n', w_text.text)

    # Generate the individual lines.
    lines = Vector{SubString}()
    for (line_i, separator_idx) in enumerate(separator_idcs)
        start_idx = if line_i == 1
            1
        else
            separator_idcs[line_i - 1] + 1
        end
        push!(lines, @view(w_text.text[start_idx, separator_idx-1]))
    end
    last_line_start = isempty(separator_idcs) ? 1 : (separator_idcs[end] + 1)
    push!(lines, @view(w_text.text[last_line_start:end]))

    # Lay out the widget on the screen.
    panel_space_x = widget_anchored_space(
        w_text.horizontal_alignment,
        w_text.anchor_point.x,
        maximum(length(line) for line in lines)
    )
    panel_space_y = widget_anchored_space(
        w_text.vertical_alignment,
        w_text.anchor_point.y,
        length(lines)
    )
    panel.space = Box2Di(
        min=Vec(min_inclusive.((panel_space_x, panel_space_y))...),
        size=Vec(size.((panel_space_x, panel_space_y))...)
    )

    # Write the lines into the widget's buffer.
    width = size(panel.space).x
    if exists(w_text.background) && w_text.background_covers_whole_space
        for relative_pos in Int32(1):size(panel.space)
            panel.backgrounds[relative_pos] = w_text.background
        end
    end
    for (line_idx, line) in enumerate(lines)
        for (char_idx, char) in enumerate(line)
            relative_pos = v2i(
                if w_text.horizontal_alignment == TextAlignment.min
                    char_idx
                elseif w_text.horizontal_alignment == TextAlignment.max
                    width - length(line) + char_idx
                elseif w_text.horizontal_alignment in (TextAlignment.centered, TextAlignment.centered_bias_max)
                    (width ÷ 2) + (char_idx - (length(line) ÷ 2))
                elseif w_text.horizontal_alignment == TextAlignment.centered_bias_min
                    (width ÷ 2) + (char_idx - ((length(line) + 1) ÷ 2))
                else
                    error("Unhandled: ", w_text.horizontal_alignment)
                end,
                line_idx
            )
            if char != ' '
                panel.foregrounds[relative_pos] = CharForegroundValue(char, w_text.color)
            end
            if exists(w_text.background) && !w_text.background_covers_whole_space
                panel.backgrounds[relative_pos] = w_text.background
            end
        end
    end
end