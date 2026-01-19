"Displays the current inventory level of some mineral"
struct WidgetInventoryMap <: AbstractWidget
    mineral::E_Mineral
    pixel::v2i
    cab::Cab
end

function widget_init!(im::WidgetInventoryMap, panel::Panel)
    panel.space = Box2Di(min=im.pixel, size=one(v2i))
end
function widget_tick!(im::WidgetInventoryMap, panel::Panel, delta_seconds::Float32)
    place_panel_char!(
        panel,
        CharDisplayValue(
            foreground=CharForegroundValue(
                MINERAL_PALETTE[im.mineral][2],
                MINERAL_PALETTE[im.mineral][1],
                clamp(im.cab.inventory[im.mineral], 0.0f0, 1.0f0),
                false
            ),
            background=CharBackgroundValue(0, 0)
        ),
        zero(v2i)
    )
end