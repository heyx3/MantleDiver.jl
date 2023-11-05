"A dead-simple ECS implementation, loosely based on Unity's model of GameObjects and Components"
module ECS

using Bplus
@using_bplus

# Define @ecs_assert and @ecs_debug
@make_toggleable_asserts ecs_

include("types.jl")
include("interface.jl")
include("operations.jl")
include("execution.jl")

export World, Entity, AbstractComponent,
       add_entity, remove_entity,
       add_component, remove_component,
       has_component, get_component, get_components,
       tick_world
end