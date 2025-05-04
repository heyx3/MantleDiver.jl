struct ControlWidgetIcon
    relative_pos::v2i
    icon::CharDisplayValue

    input_name::String # ID in the B+ Input service for holding the control down
    disabled_density_scale::Float32

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
        foreground = control.icon.foreground
        background = control.icon.background

        if exists(background)
            #TODO: Modifier should be false if idx is 0 and ANY modifier is pressed
            modifier::Bool = (control.modifier_idx < 1) || get_button(INPUT_MODIFIERS[control.modifier_idx][1])
            key::Bool = get_button(control.input_name)

            density = background.density *
                if modifier && !key
                    control.modifier_density_scale
                elseif !key
                    control.disabled_density_scale
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