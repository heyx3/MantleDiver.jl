using Drill8
const D8 = Drill8

using Test

using Bplus
using Bplus.Math

@testset "Animation data" begin
    @testset "rotate_cab_movement()" begin
        @test D8.rotate_cab_movement(
            v3f(4.4, 5.5, 6.6),
            D8.CabMovementDir(
                1, 1, 1
            )
        ) == v3f(4.4, 5.5, 6.6)
        @test D8.rotate_cab_movement(
            v3f(4.4, 5.5, 6.6),
            D8.CabMovementDir(
                1, 1, -1
            )
        ) == v3f(4.4, -5.5, 6.6)
        @test D8.rotate_cab_movement(
            v3f(4.4, 5.5, 6.6),
            D8.CabMovementDir(
                1, -1, 1
            )
        ) == v3f(-4.4, -5.5, 6.6)
        @test D8.rotate_cab_movement(
            v3f(4.4, 5.5, 6.6),
            D8.CabMovementDir(
                1, -1, -1
            )
        ) == v3f(-4.4, 5.5, 6.6)
        @test D8.rotate_cab_movement(
            v3f(4.4, 5.5, 6.6),
            D8.CabMovementDir(
                2, -1, 1
            )
        ) == v3f(-5.5, -4.4, 6.6)
        @test D8.rotate_cab_movement(
            v3f(4.4, 5.5, 6.6),
            D8.CabMovementDir(
                2, -1, -1
            )
        ) == v3f(5.5, -4.4, 6.6)
    end
end