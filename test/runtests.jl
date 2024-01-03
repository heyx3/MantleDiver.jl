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

@testset "Grid Math" begin
    @testset "is_min_half_of_grid_cell()" begin
        @test !D8.is_min_half_of_grid_cell(0.01)
        @test !D8.is_min_half_of_grid_cell(0.49)

        @test D8.is_min_half_of_grid_cell(0.51)
        @test D8.is_min_half_of_grid_cell(0.59)
        @test !D8.is_min_half_of_grid_cell(1.01)

        @test D8.is_min_half_of_grid_cell(-0.01)
        @test D8.is_min_half_of_grid_cell(-0.3)
        @test !D8.is_min_half_of_grid_cell(-0.52)
        @test !D8.is_min_half_of_grid_cell(-0.89)
        @test D8.is_min_half_of_grid_cell(-1.01)

        @test !D8.is_min_half_of_grid_cell(45.3)

        @test D8.is_min_half_of_grid_cell(v3f(0.75, 10.1, -0.6)) ==
                v3b(true, false, false)
    end
    @testset "Coordinate Conversions" begin
        @test D8.chunk_idx(v3i(0, 0, 0)) == v3i(0, 0, 0)
        @test D8.chunk_idx(v3i(-1, 1, -1)) == v3i(-1, 0, -1)
        @test D8.chunk_idx(v3i(5, 10, 19)) == v3i(0, 1, 2)
        @test D8.chunk_idx(v3i(-5, -10, -19)) == v3i(-1, -2, -3)

        @test D8.chunk_first_grid_idx(v3i(0, 0, 0)) == v3i(0, 0, 0)
        @test D8.chunk_first_grid_idx(v3i(-1, 3, -9)) == v3i(-8, 24, -72)
        @test D8.chunk_first_grid_idx(v3i(2, -1, 3)) == v3i(16, -8, 24)

        @test D8.chunk_grid_idx(v3i(0, 0, 0), v3i(3, 4, 5)) ==
                v3i(4, 5, 6)
        @test D8.chunk_grid_idx(v3i(-1, 2, 0), v3i(-7, 21, 0)) ==
                v3i(2, 6, 1)
    end
end

@testset "World grid and chunking" begin
    @component TestGridElement {entitySingleton} {require: D8.GridElement} begin
        i::Int
    end

    # "Associates a string with each grid element"
    @component TestBulkGridElement<:D8.AbstractBulkGridElement {worldSingleton} begin
        lookup::Dict{v3i, String}

        function CONSTRUCT()
            SUPER()
            this.lookup = Dict{v3i, String}()
        end

        function create_at(i::v3i, s::String)
            @bp_check(!haskey(this.lookup, i),
                      "Trying to create string at location which already has it: ",
                        i, " => '", this.lookup[i], "'")
            this.lookup[i] = s
            return nothing
        end
        function destroy_at(i::v3i)::String
            @bp_check(haskey(this.lookup, i),
                      "Trying to destroy nonexistent string at ", i)
            deleted = this.lookup[i]
            delete!(this.lookup, i)
            return deleted
        end

        function data_at(i::v3i)::Optional{String}
            return get(this.lookup, i, nothing)
        end

        is_passable(i::v3i) = true
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
    bulk::TestBulkGridElement = add_component(grid_entity, TestBulkGridElement)

    @test D8.chunk_at(grid, v3f(1, 2.3, 6)) === nothing
    @test D8.entity_at(grid, v3i(1, 2, 6)) === nothing

    chunk = D8.chunk_at!(grid, v3f(1.1, 2.2, 5.91))
    @test chunk isa D8.GridChunk
    @test chunk.idx == v3i(0, 0, 0)
    e_1_2_6 = D8.entity_at(grid, v3i(1, 2, 6))
    @test e_1_2_6 isa Entity
    g_1_2_6 = get_component(e_1_2_6, D8.GridElement)
    c_1_2_6 = get_component(e_1_2_6, TestGridElement)
    @test c_1_2_6.i == test_rule(v3i(1, 2, 6))

    remove_entity(wo, e_1_2_6)
    @test D8.entity_at(grid, v3i(1, 2, 6)) === nothing

    # Add some bulk entities.
    bulk.create_at(v3i(2, 4, 5), "2/4/5")
    chunk.elements[D8.chunk_grid_idx(v3i(0, 0, 0), v3i(2, 4, 5))] = bulk
    @test !isa(D8.entity_at(grid, v3i(1, 4, 5)), D8.BulkEntity)
    @test !isa(D8.entity_at(grid, v3i(-4, 5, -20)), D8.BulkEntity)
    @test D8.entity_at(grid, v3i(2, 4, 5)) == (bulk, v3i(2, 4, 5))
    @test bulk.data_at(v3i(2, 4, 5)) == "2/4/5"

    @test D8.entity_at(grid, v3i(1, 3, 6)) isa Entity
    remove_component(grid_entity, chunk)
    @test D8.entity_at(grid, v3i(1, 3, 6)) === nothing
    @test length(bulk.lookup) == 0
end