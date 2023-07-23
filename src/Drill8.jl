module Drill8

using Random

using Bplus
@using_bplus


const PI2 = Float32(2π)


@bp_enum(RockTypes::UInt8,
    empty = 0,
    plain = 1,
    gold = 2
)
const RockGrid = Array{RockTypes, 3}


include("cab.jl")


mutable struct Player
    grid_pos::v3f # Integer values represent the center of a rock grid cell.
    move_target::Optional{v3i} # The grid cell the player is moving towards
end
player_grid_idx(p::Player) = round(p.grid_pos)


function julia_main()::Cint
    @game_loop begin
        INIT(
            v2i(1280, 720), "Drill8"
        )

        SETUP = begin
            Random.seed!(0xd8d8d8d8)

            # Generate the rock grid.
            rock_grid = fill(RockTypes.plain, 4, 4, 16)
            # Keep the top layer empty.
            rock_grid[:, :, 1] .= RockTypes.empty
            # Randomly remove pieces of rock.
            n_subtractions::Int = length(rock_grid) // 5
            for _ in 1:n_subtractions
                local pos::Vec3{<:Integer}
                @do_while begin
                    pos = rand(1:vsize(rock_grid))
                end rock_grid[pos] != RockTypes.plain
                rock_grid[pos] = RockTypes.empty
            end
            # Ensure there's at least one solid rock underneath the top layer,
            #    for the player to spawn on.
            if all(r -> (r==RockTypes.empty), @view rock_grid[:, :, 2])
                fill_pos = rand(v3i(1, 1, 2) : v3i(vsize(rock_grid).xy, 2))
                rock_grid[fill_pos...] = RockTypes.plain
            end
            # Insert some pieces of gold.
            n_golds::Int = 5
            for _ in 1:n_golds
                local pos::Vec3{Int}
                @do_while begin
                    pos = rand(1:vsize(rock_grid))
                end rock_grid[pos] != RockTypes.plain
                rock_grid[pos] = RockTypes.gold
            end

            # Place the player's cab in the top layer, above solid rock.
            cab::CabState = CabState(
                begin
                    local pos::Vec2{Int}
                    @do_while begin
                        pos = rand(1:vsize(rock_grid).xy)
                    end
                    pos
                end,
                nothing,
                v3f(1, 0, 0)
            )

            elapsed_seconds::Float32 = @f32(0)
        end

        LOOP = begin
            elapsed_seconds += LOOP.delta_seconds
            update_cab!(cab, LOOP.delta_seconds)

            #TODO: Debug render with dear imgui
        end
    end
    return 0
end

end # module