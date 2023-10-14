"
Ticks all components of the given type.
This approach to ticking significantly reduces the cost of dynamic dispatch.
"
function tick_components(world::World, ::Type{T}) where {T<:AbstractComponent}
end

function tick_world(world::World, delta_seconds::Float32)
    if world.time_scale <= 0
        return nothing
    end
    world.delta_seconds = delta_seconds * world.time_scale
    world.elapsed_seconds += world.delta_seconds

    for entity in world.entities
        tick_entity(entity)
    end

    return nothing
end