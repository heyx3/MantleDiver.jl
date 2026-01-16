"
A single pixel in the framebuffer, displaying values based on a player input.

Many fields can be either constant values, or `Pair{T, T}`
  using the first value if the input isn't held down, and the second value if it is.
"
struct ControlWidgetIcon
    relative_pos::v2i
    icon::Union{CharDisplayValue, Pair{CharDisplayValue, CharDisplayValue}}

    input_name::Optional{String} # ID in the B+ Input service for holding the control down;
                                 #  `nothing` if only the modifier key is needed
    disabled_density_scale::Union{Float32, Pair{Float32, Float32}}

    modifier_idx::Int # 0 if no modifier needed
    modifier_density_scale::Float32 # If modifier but not key is pressed
end

struct WidgetControlMap <: AbstractWidget
    resolution::v2u
    controls::Vector{ControlWidgetIcon}
end

function widget_init!(cm::WidgetControlMap, panel::Panel)
    panel.space = Box2Di(
        min=one(v2i),
        size=cm.resolution
    )
end
function widget_tick!(cm::WidgetControlMap, panel::Panel, delta_seconds::Float32)
    empty!(panel.foregrounds)
    empty!(panel.backgrounds)

    for control in cm.controls
        #TODO: Modifier should be false if idx is 0 and ANY modifier is pressed
        modifier::Bool = (control.modifier_idx < 1) || get_button(INPUT_MODIFIERS[control.modifier_idx][1])
        key::Bool = if isnothing(control.input_name)
            modifier
        else
            get_button(control.input_name)
        end

        icon = if control.icon isa CharDisplayValue
            control.icon
        else
            (modifier && key) ? control.icon[2] : control.icon[1]
        end
        foreground = icon.foreground
        background = icon.background

        if exists(background)
            density = background.density *
                if modifier && !key
                    control.modifier_density_scale
                elseif !key
                    if control.disabled_density_scale isa Float32
                        control.disabled_density_scale
                    else
                        if modifier && key
                            control.disabled_density_scale[2]
                        else
                            control.disabled_density_scale[1]
                        end
                    end
                else
                    one(Float32)
                end
                background = CharBackgroundValue(background.color, density)
        end

        place_panel_char!(panel,
                          CharDisplayValue(foreground=foreground, background=background),
                          control.relative_pos)
    end
end