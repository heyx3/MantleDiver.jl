using Drill8
using Drill8.ECS

const D8 = Drill8
const ECS = D8.ECS


# Set up debug asserts:
ECS.ecs_asserts_enabled() = true

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