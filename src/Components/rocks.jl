mutable struct GoldComponent <: AbstractComponent end
ECS.require_components(::Type{GoldComponent}) = (GridElementComponent, )
ECS.allow_multiple(::Type{GoldComponent}) = false