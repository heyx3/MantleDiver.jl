@component MainGenerator <: GridGenerator begin
    seed::UInt32
    player_start_pos::v3i

    gaps_scale::Float32 # Larger than 1
    gaps_severity::Float32 # Between 0 and 1

    minerals_scale::Float32 # Larger than 1
    minerals_rarity::Float32 # Between 0 and 1
    minerals_concentration::Float32 # Exponent (more than 0, default is 1)

    function generate(grid_pos::v3i)
        if sum(abs(grid_pos - this.player_start_pos)) <= 2
            return nothing
        elseif perlin(grid_pos / this.gaps_scale) < this.gaps_severity
            return nothing
        else
            return make_rock(world, grid_pos, Rock(
                PerMineral{Float32}() do mineral_idx::Int
                    mineral::E_Mineral = Mineral.from(mineral_idx - 1)

                    mineral_noise = perlin(
                        grid_pos / this.minerals_scale,
                        tuple(
                            0x7890a3b1,
                            this.seed,
                            # The mineral index is a very low number.
                            # Spread it across an entire UInt32
                            #    so we can spend less time warming up the PRNG.
                            UInt32(mineral_idx) |
                              UInt32(mineral_idx << 9) |
                              UInt32(mineral_idx << 19) |
                              UInt32(mineral_idx << 29),
                        ),
                        Val(PrngStrength.weak),
                        identity,
                        identity
                    )
                    mineral_noise = saturate(inv_lerp(this.minerals_rarity, @f32(1), mineral_noise))
                    mineral_noise ^= this.minerals_concentration
                    return mineral_noise
                end
            ))[1]
        end
    end
end