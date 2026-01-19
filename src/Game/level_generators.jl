@component MainGenerator <: GridGenerator begin
    seed::UInt32
    player_start_pos::v3i

    gaps_scale::Float32 # Larger than 1
    gaps_severity::Float32 # Between 0 and 1

    minerals_scale:: Float32 # Larger than 1
    minerals_rarity::Float32 # Between 0 and 1
    minerals_concentration::Float32 # Exponent (more than 0, default is 1)

    function generate(grid_pos::v3i)::Optional{BulkElements}
        if sum(abs(grid_pos - this.player_start_pos)) <= 2
            return nothing
        elseif perlin(grid_pos / this.gaps_scale) < this.gaps_severity
            return nothing
        else
            rock_minerals = PerMineral{Float32}() do mineral_idx::Int
                mineral::E_Mineral = Mineral.from(mineral_idx - 1)

                mineral_noise = Bplus.perlin(
                    grid_pos / this.minerals_scale,
                    tuple(
                        0x7890a3b1,
                        this.seed,
                        UInt8(mineral_idx),
                    ),
                    Val(Bplus.PrngStrength.medium),
                    identity,
                    identity
                )
                mineral_noise = saturate(inv_lerp(this.minerals_rarity, @f32(1), mineral_noise))
                mineral_noise ^= this.minerals_concentration
                return (mineral_noise > 0.01) ? mineral_noise : 0.0f0
            end
            max_mineral_strength = maximum(rock_minerals)
            rock_minerals = map(f -> (f==max_mineral_strength ? f : 0.0f0), rock_minerals)
            return make_rock(world, grid_pos, Rock(rock_minerals))[1]
        end
    end
end