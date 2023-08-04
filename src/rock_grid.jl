@bp_enum(RockTypes::UInt8,
    empty = 0,
    plain = 1,
    gold = 2
)
const RockGrid = Array{E_RockTypes, 3}

# Integer values represent the center of a rock grid cell.
rock_grid_idx(pos::v3f) = convert(v3i, round(pos))

grid_pos_free(grid_pos::Vec3{<:AbstractFloat}, grid::RockGrid) = grid_pos_free(rock_grid_idx(grid_pos), grid)
grid_pos_free(grid_pos::Vec3{<:Integer}, grid::RockGrid) = is_touching(Box3Di(min=one(v3i), size=vsize(grid)),
                                                                       grid_pos) &&
                                                           (grid[grid_pos] == RockTypes.empty)