using Drill8
const D8 = Drill8

using Bplus
@using_bplus

# Set up debug asserts:
BplusTools.ECS.bp_ecs_asserts_enabled() = true
D8.d8_asserts_enabled() = true


using Test

@testset "Animation data" begin
    @testset "rotate_cab_movement()" begin
        @test D8.rotate_cab_movement(
            v3f(4.4, 5.5, 6.6),
            D8.CabMovementDir(
                D8.GridDirections.pos_x, 1
            )
        ) == v3f(4.4, 5.5, 6.6)
        @test D8.rotate_cab_movement(
            v3f(4.4, 5.5, 6.6),
            D8.CabMovementDir(
                D8.GridDirections.pos_x, -1
            )
        ) == v3f(4.4, -5.5, 6.6)
        @test D8.rotate_cab_movement(
            v3f(4.4, 5.5, 6.6),
            D8.CabMovementDir(
                D8.GridDirections.neg_x, 1
            )
        ) == v3f(-4.4, -5.5, 6.6)
        @test D8.rotate_cab_movement(
            v3f(4.4, 5.5, 6.6),
            D8.CabMovementDir(
                D8.GridDirections.neg_x, -1
            )
        ) == v3f(-4.4, 5.5, 6.6)
        @test D8.rotate_cab_movement(
            v3f(4.4, 5.5, 6.6),
            D8.CabMovementDir(
                D8.GridDirections.neg_y, 1
            )
        ) == v3f(-5.5, -4.4, 6.6)
        @test D8.rotate_cab_movement(
            v3f(4.4, 5.5, 6.6),
            D8.CabMovementDir(
                D8.GridDirections.neg_y, -1
            )
        ) == v3f(5.5, -4.4, 6.6)
    end
end

@testset "World grid and chunking" begin
    @component TestGridElement {entitySingleton} {require: D8.GridElement} begin
        i::Int
    end

    "Picks a value for the given test grid element"
    test_rule(idx::v3i)::Int = (idx.x * (17278 + idx.y)) ⊻ ~(idx.z)

    @component TestGenerator <: D8.GridGenerator begin
        generate(i::v3i) = let e = add_entity(world)
            add_component(e, D8.DiscretePosition, i)
            add_component(e, TestGridElement, test_rule(i))
            e
        end
    end

    wo = World()
    grid_entity = add_entity(wo)

    generator = add_component(grid_entity, TestGenerator)
    grid = add_component(grid_entity, D8.GridManager)

    @test D8.chunk_at(grid, v3f(1, 2.3, 6)) === nothing
    @test D8.entity_at(grid, v3i(1, 2, 6)) === nothing

    chunk = D8.chunk_at!(grid, v3f(1.1, 2.2, 5.91))
    @test chunk !== nothing
    e_1_2_6 = D8.entity_at(grid, v3i(1, 2, 6))
    @test e_1_2_6 !== nothing
    g_1_2_6 = get_component(e_1_2_6, D8.GridElement)
    c_1_2_6 = get_component(e_1_2_6, TestGridElement)
    @test c_1_2_6.i == test_rule(v3i(1, 2, 6))

    remove_entity(wo, e_1_2_6)
    @test D8.entity_at(grid, v3i(1, 2, 6)) === nothing

    @test D8.entity_at(grid, v3i(1, 3, 6)) !== nothing
    remove_component(grid_entity, chunk)
    @test D8.entity_at(grid, v3i(1, 3, 6)) === nothing
end