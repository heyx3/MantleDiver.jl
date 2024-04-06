# Minerals are named after the thing they're spent on.
@bp_enum(Mineral,
    storage,
    hull,
    drill,
    specials,
    sensors,
    maneuvers
)

"Some per-mineral data, stored in an immutable array"
const PerMineral{T} = Vec{length(Mineral.instances()), T}
@inline getindex(pm::PerMineral, m::E_Mineral) = pm[Int32(m)]

"Per-rock data, stored in a bulk grid entity"
struct Rock
    minerals::PerMineral{Float32}
end

const RockBulkElements = BulkElements{Rock}
bulk_data_is_passable(::RockBulkElements, ::v3i, ::Rock) = false


###############################


"A rock's response to being drilled"
@component RockDrillResponse <: DrillResponse {require: RockBulkElements} begin
    # Default behavior is fine
end


#################################


const ROCK_DEBUG_COLOR = vRGBf(93, 76, 82) / 255
const MINERAL_DEBUG_COLORS = PerMineral{vRGBf}(
    vRGBf(141, 191, 179),
    vRGBf(242, 235, 192),
    vRGBf(243, 180, 98),
    vRGBf(240, 96, 96),
    vRGBf(47, 127, 51),
    vRGBf(244, 64, 52)
) / 255
const MINERAL_MAX_DEBUG_COLOR_POINT = @f32(1)
const MINERAL_DEBUG_COLOR_DROPOFF = @f32(1.7)

# "Draws the bulk of rocks"
@component DebugGuiVisuals_Rocks <: DebugGuiVisuals {require: RockBulkElements} begin
    bulk::RockBulkElements
    function CONSTRUCT()
        SUPER()
        this.bulk = get_component(entity, RockBulkElements)
    end
    draw_order() = typemin(Int64)
    function visualize(data::DebugGuiRenderData)
        for voxel_pos_2D::v2i in grid_idx(min_inclusive(data.world_voxel_range)):grid_idx(max_inclusive(data.world_voxel_range))
            voxel_pos::v3i =
                if data.horizontal_axis == 1
                    v3i(voxel_pos_2D.x, data.horizontal_depth, voxel_pos_2D.y)
                elseif data.horizontal_axis == 2
                    v3i(data.horizontal_depth, voxel_pos_2D.x, voxel_pos_2D.y)
                else
                    error(data.horizontal_axis)
                end
            if voxel_pos[data.other_horizontal_axis] == data.horizontal_depth
                world_rect = Box3Df(center=voxel_pos, size=one(v3f))
                gui_rect = world_to_gui(world_rect, data)
                rock = bulk_data_at(this.bulk, voxel_pos)
                if isnothing(rock)
                    continue
                end

                color::vRGBf = ROCK_DEBUG_COLOR
                for (mineral_color, mineral_strength) in zip(MINERAL_DEBUG_COLORS, rock.minerals)
                    color_strength = saturate(mineral_strength / MINERAL_MAX_DEBUG_COLOR_POINT)
                    color_strength ^= MINERAL_DEBUG_COLOR_DROPOFF
                    color = lerp(color, mineral_color, color_strength)
                end

                CImGui.ImDrawList_AddRectFilled(
                    data.draw_list,
                    min_inclusive(gui_rect).xy,
                    max_inclusive(gui_rect).xy,
                    CImGui.ImVec4(color..., 1),
                    @f32(4),
                    CImGui.LibCImGui.ImDrawFlags_None
                )
            end
        end
    end
end