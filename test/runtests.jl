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

@testset "ECS" begin
    # Component1 is not a singleton, and requires a Component2.
    mutable struct Component1 <: AbstractComponent
        i::Int
        Component1(i = -1) = new(i)
    end
    ECS.allow_multiple(::Type{Component1}) = true
    ECS.require_components(::Type{Component1}) = (Component2, )

    # Component2 is a singleton and has no requirements.
    mutable struct Component2 <: AbstractComponent
        s::String
        Component2(s = "") = new(s)
    end
    ECS.allow_multiple(::Type{Component2}) = false
    ECS.require_components(::Type{Component2}) = ()

    # Component3 is a singleton, and requires a Component4.
    mutable struct Component3 <: AbstractComponent end
    ECS.allow_multiple(::Type{Component3}) = false
    ECS.require_components(::Type{Component3}) = (Component2, Component4)

    # Component4 is not a singleton, and requires a Component3.
    mutable struct Component4 <: AbstractComponent end
    ECS.allow_multiple(::Type{Component4}) = true
    ECS.require_components(::Type{Component4}) = (Component3, )

    # Component5 and Component6 are subtypes of an abstract component type.
    abstract type Component_5_or_6 <: AbstractComponent end
    mutable struct Component5 <: Component_5_or_6 end
    mutable struct Component6 <: Component_5_or_6 end
    ECS.allow_multiple(::Type{Component5}) = true
    ECS.allow_multiple(::Type{Component6}) = true

    # Define references to all the testable data.
    world = World()
    entities = Entity[ ]
    c1s = Component1[ ]
    c2 = Ref{Component2}()
    c2_2 = Ref{Component2}()
    c3 = Ref{Component3}()
    c4s = Component4[ ]
    c5s = Component5[ ]
    c6s = Component6[ ]
    EMPTY_ENTITY_COMPONENT_LOOKUP = Dict{Type{<:AbstractComponent}, Set{AbstractComponent}}()

    @testset "Entities" begin
        push!(entities, add_entity(world))
        @test world.entities == entities
        @test world.component_lookup ==
                Dict(e=>EMPTY_ENTITY_COMPONENT_LOOKUP for e in entities)

        push!(entities, add_entity(world))
        @test world.entities == entities
        Dict(e=>EMPTY_ENTITY_COMPONENT_LOOKUP for e in entities)

        push!(entities, add_entity(world))
        @test world.entities == entities
        Dict(e=>EMPTY_ENTITY_COMPONENT_LOOKUP for e in entities)

        remove_entity(world, entities[2])
        deleteat!(entities, 2)
        @test world.entities == entities
        Dict(e=>EMPTY_ENTITY_COMPONENT_LOOKUP for e in entities)

        # Test that other stuff is unaffected.
        @test isempty(world.component_counts)
        @test world.time_scale == 1
    end

    @testset "Components" begin
        @testset "Hierarchies" begin
            @test collect(get_component_types(Component2)) == [ Component2 ]
            @test collect(get_component_types(Component5)) == [ Component5, Component_5_or_6 ]
            @test collect(get_component_types(Component_5_or_6)) == [ Component_5_or_6 ]
        end

        @testset "Adding a C2 to E1" begin
            c2[] = add_component(Component2, entities[1], "hi world")
            @test c2[].s == "hi world"

            @test entities[1].components == [ c2[] ]

            @test world.component_lookup == Dict(
                entities[1] => Dict(Component2=>Set([ c2[] ])),
                (e => EMPTY_ENTITY_COMPONENT_LOOKUP for e in entities[2:end])...
            )
            @test world.entity_lookup == Dict(
                Component2 => Set([ entities[1] ])
            )

            @test world.component_counts == Dict(Component2 => 1)
        end
        @testset "Adding some C1s to E1" begin
            push!(c1s, add_component(Component1, entities[1]))
            push!(c1s, add_component(Component1, entities[1]))
            push!(c1s, add_component(Component1, entities[1]))

            @test entities[1].components == [ c2[], c1s... ]

            @test world.component_lookup == Dict(
                entities[1] => Dict(
                    Component2 => Set([ c2[] ]),
                    Component1 => Set(c1s)
                ),
                (e => EMPTY_ENTITY_COMPONENT_LOOKUP for e in entities[2:end])...
            )
            @test world.entity_lookup == Dict(
                Component2 => Set([ entities[1] ]),
                Component1 => Set([ entities[1] ])
            )
            @test world.component_counts == Dict(
                Component1 => 3,
                Component2 => 1
            )
        end
        @testset "Removing the middle C1" begin
            remove_component(c1s[2], entities[1])
            deleteat!(c1s, 2)

            @test entities[1].components == [ c2[], c1s... ]
            @test entities[2].components == [ ]

            @test world.component_lookup == Dict(
                entities[1] => Dict(
                    Component2 => Set([ c2[] ]),
                    Component1 => Set(c1s)
                ),
                (e => EMPTY_ENTITY_COMPONENT_LOOKUP for e in entities[2:end])...
            )
            @test world.entity_lookup == Dict(
                Component2 => Set([ entities[1] ]),
                Component1 => Set([ entities[1] ])
            )
            @test world.component_counts == Dict(
                Component1 => 2,
                Component2 => 1
            )
        end

        @testset "Component queries" begin
            @test has_component(entities[1], Component1)
            @test has_component(entities[1], Component2)
            @test !has_component(entities[1], Component3)
            @test !has_component(entities[1], Component4)

            @test !has_component(entities[2], Component1)
            @test !has_component(entities[2], Component2)
            @test !has_component(entities[2], Component3)
            @test !has_component(entities[2], Component4)

            @test get_component(entities[1], Component2) == c2[]
            @test Set(get_components(entities[1], Component1)) ==
                    Set(c1s)

            @test get_component(world, Component2) == (c2[], entities[1])
            @test Set(get_components(world, Component1)) ==
                    Set(zip(c1s, Iterators.repeated(entities[1])))
        end

        @testset "Recursive component requirements" begin
            push!(c4s, add_component(Component4, entities[2]))
            @test count(x->true, get_components(world, Component4)) === 1
            @test count(x->true, get_components(entities[2], Component4)) === 1

            # Adding Component4 should have added Component3 to the same entity.
            @test count(x->true, get_components(world, Component3)) === 1
            @test count(x->true, get_components(entities[2], Component3)) === 1
            c3[] = get_component(world, Component3)[1]

            # It should also have added Component2.
            @test has_component(entities[2], Component2)
            c2_2[] = get_component(entities[2], Component2)

            @test entities[1].components == [ c2[], c1s... ]
            @test entities[2].components == [ c2_2[], c3[], c4s... ]

            @test Set(get_components(world, Component2)) ==
                    Set([ (c2[], entities[1]), (c2_2[], entities[2]) ])
            @test world.component_lookup == Dict(
                entities[1] => Dict(
                    Component2 => Set([ c2[] ]),
                    Component1 => Set(c1s)
                ),
                entities[2] => Dict(
                    Component3 => Set([ c3[] ]),
                    Component4 => Set(c4s),
                    Component2 => Set([ c2_2[] ])
                )
            )
            @test world.entity_lookup == Dict(
                Component2 => Set([ entities[1], entities[2] ]),
                Component1 => Set([ entities[1] ]),
                Component3 => Set([ entities[2] ]),
                Component4 => Set([ entities[2] ]),
            )
            @test world.component_counts == Dict(
                Component1 => 2,
                Component2 => 2,
                Component3 => 1,
                Component4 => 1
            )
        end

        @testset "Component inheritance part 1" begin
            # Add Component5 and check that it's also registered under its abstract parent type.

            push!(c5s, add_component(Component5, entities[1]))
            @test count(x->true, get_components(entities[1], Component5)) == 1
            @test count(x->true, get_components(entities[1], Component_5_or_6)) == 1
            @test count(x->true, get_components(world, Component5)) == 1
            @test count(x->true, get_components(world, Component_5_or_6)) == 1

            @test entities[1].components == [ c2[], c1s..., c5s... ]
            @test entities[2].components == [ c2_2[], c3[], c4s... ]

            @test Set(get_components(world, Component5)) ==
                    Set([ (c5s[1], entities[1]) ])
            @test Set(get_components(world, Component_5_or_6)) ==
                    Set([ (c5s[1], entities[1]) ])

            @test world.component_lookup == Dict(
                entities[1] => Dict(
                    Component2 => Set([ c2[] ]),
                    Component1 => Set(c1s),
                    Component5 => Set(c5s),
                    Component_5_or_6 => Set(c5s)
                ),
                entities[2] => Dict(
                    Component3 => Set([ c3[] ]),
                    Component4 => Set(c4s),
                    Component2 => Set([ c2_2[] ])
                )
            )
            @test world.entity_lookup == Dict(
                Component2 => Set([ entities[1], entities[2] ]),
                Component1 => Set([ entities[1] ]),
                Component3 => Set([ entities[2] ]),
                Component4 => Set([ entities[2] ]),
                Component5 => Set([ entities[1] ]),
                Component_5_or_6 => Set([ entities[1] ])
            )
            @test world.component_counts == Dict(
                Component1 => 2,
                Component2 => 2,
                Component3 => 1,
                Component4 => 1,
                Component5 => 1,
                Component_5_or_6 => 1,
            )
        end
        @testset "Component inheritance part 2" begin
            # Add Component6 and check that it's also registered under its abstract parent type,
            #    shared with the Component5 added in the previous test.

            push!(c6s, add_component(Component6, entities[1]))
            @test count(x->true, get_components(entities[1], Component6)) == 1
            @test count(x->true, get_components(entities[1], Component_5_or_6)) == 2
            @test count(x->true, get_components(world, Component6)) == 1
            @test count(x->true, get_components(world, Component_5_or_6)) == 2

            @test entities[1].components == [ c2[], c1s..., c5s..., c6s... ]
            @test entities[2].components == [ c2_2[], c3[], c4s... ]

            @test Set(get_components(world, Component6)) ==
                    Set([ (c6s[1], entities[1]) ])
            @test Set(get_components(world, Component_5_or_6)) ==
                    Set([ (c5s[1], entities[1]), (c6s[1], entities[1]) ])

            @test world.component_lookup == Dict(
                entities[1] => Dict(
                    Component2 => Set([ c2[] ]),
                    Component1 => Set(c1s),
                    Component5 => Set(c5s),
                    Component6 => Set(c6s),
                    Component_5_or_6 => Set([ c5s..., c6s... ])
                ),
                entities[2] => Dict(
                    Component3 => Set([ c3[] ]),
                    Component4 => Set(c4s),
                    Component2 => Set([ c2_2[] ])
                )
            )
            @test world.entity_lookup == Dict(
                Component2 => Set([ entities[1], entities[2] ]),
                Component1 => Set([ entities[1] ]),
                Component3 => Set([ entities[2] ]),
                Component4 => Set([ entities[2] ]),
                Component5 => Set([ entities[1] ]),
                Component6 => Set([ entities[1] ]),
                Component_5_or_6 => Set([ entities[1] ])
            )
            @test world.component_counts == Dict(
                Component1 => 2,
                Component2 => 2,
                Component3 => 1,
                Component4 => 1,
                Component5 => 1,
                Component6 => 1,
                Component_5_or_6 => 2,
            )
        end
    end
end