"Gets whether an entity can hold more than one of the given type of component"
allow_multiple(::Type{<:AbstractComponent})::Bool = true

"Gets the types of components required by the given component"
require_components(::Type{<:AbstractComponent})::Tuple = ()


"
Creates a new component that will be attached to the given entity.

Any dependent components named in `require_components()` will already be available,
    except in recursive cases where multiple components require each other.

By default, invokes the component's constructor and passes the entity.
"
create_component(T::Type{<:AbstractComponent}, e::Entity)::T = T(e)

"Cleans up a component that was attached to the given entity"
destroy_component(::AbstractComponent, ::Entity, is_entity_dying::Bool) = nothing


"
Updates the given component attached to the given entity.

Note that the entity reference is only given for convenience;
    the component will always have the same Entity owner that it did when it was created.
"
tick_component(::AbstractComponent, ::Entity) = nothing

export allow_multiple, require_components,
       create_component, destroy_component,
       tick_component