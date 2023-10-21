##   Position   ##

"
Something that exists in space, either discretely in the rock voxel grid or continuously.

If a specific subtype is not specified, the entity's position will be discrete by default.
"
abstract type AbstractVoxelPositionComponent <: AbstractComponent end
ECS.allow_multiple(::Type{<:AbstractVoxelPositionComponent}) = false
ECS.create_component(::Type{AbstractVoxelPositionComponent}, e::Entity) = DiscreteVoxelPosition()

get_voxel_position(c::AbstractVoxelPositionComponent)::v3i = error(
    "get_voxel_position(::",
    typeof(c),
    ") not implemented"
)
get_precise_position(c::AbstractVoxelPositionComponent)::v3f = error(
    "get_precise_position(::",
    typeof(c),
    ") not implemented"
)

get_voxel_position(e::Entity)::v3i = get_voxel_position(get_component(e, AbstractVoxelPositionComponent))
get_precise_position(e::Entity)::v3f = get_precise_position(get_component(e, AbstractVoxelPositionComponent))


# Discrete Position #

"Positioned in terms of an element of the rock voxel grid."
mutable struct DiscreteVoxelPosition <: AbstractVoxelPositionComponent
    pos::v3i
    DiscreteVoxelPosition(pos = zero(v3i)) = new(pos)
end
get_voxel_position(d::DiscreteVoxelPosition) = d.pos
get_precise_position(d::DiscreteVoxelPosition) = convert(v3f, d.pos)


# Continuous Position #

"
A position somewhere within the rock voxel grid.
The center of each voxel is at an integer coordinate.
"
mutable struct ContinuousPosition <: AbstractVoxelPositionComponent
    pos::v3f
    ContinuousPosition(pos = zero(v3f)) = new(pos)
end
get_voxel_position(c::ContinuousPosition) = convert(v3i, round(c.pos))
get_precise_position(c::ContinuousPosition) = c


##   Orientation   ##

@kwdef mutable struct OrientationComponent <: AbstractComponent
    rot::fquat = fquat()
end

get_orientation(e::Entity) = get_component(e, OrientationComponent).rot


##   Cosmetic Transform   ##

"Represents a temporary visual offset to position/orientation, in local space"
@kwdef mutable struct CosmeticOffsetComponent <: AbstractComponent
    pos::v3f = zero(v3f)
    rot::fquat = fquat()
end

"Gets the cosmetic position of an entity, handling the case where the entity doesn't have a cosmetic offset"
function get_cosmetic_pos(e::Entity)
    pos = get_precise_position(e)
    for cosmetic::CosmeticOffsetComponent in get_components(e, CosmeticOffsetComponent)
        pos += cosmetic.pos
    end
    return pos
end

"Gets the cosmetic rotation of an entity, handling the case where the entity doesn't have a cosmetic offset"
function get_cosmetic_rot(e::Entity)
    rot::fquat = get_orientation(e)
    for cosmetic::CosmeticOffsetComponent in get_components(e, CosmeticOffsetComponent)
        rot <<= cosmetic.rot
    end
    return rot
end


##  Helper Functions  ##

"Gets the 4x4 world transform matrix for an entity that has position and orientation components"
get_world_transform(e::Entity) = get_world_transform(
    get_component(e, AbstractVoxelPositionComponent),
    get_component(e, OrientationComponent)
)
get_world_transform(p::AbstractVoxelPositionComponent,
                    o::OrientationComponent,
                    scale::v3f = one(v3f)) = m4_world(
    get_precise_position(p),
    o.rot,
    scale
)


##   Grid Directions   ##

const GridDirection = Bplus.GL.E_CubeFaces
const GridDirections = Bplus.GL.CubeFaces

"Gets the axis of the given direction (1=X, 2=Y, 3=Z)"
function grid_axis(dir::GridDirection)::UInt8
    return if dir in (GridDirections.pos_x, GridDirections.neg_x)
        1
    elseif dir in (GridDirections.pos_y, GridDirections.neg_y)
        2
    elseif dir in (GridDirections.pos_z, GridDirections.neg_z)
        3
    else
        error(dir)
    end
end
"Gets the sign of the given direction (positive=+1, negative=-1)"
function grid_sign(dir::GridDirection)::Int8
    return if dir in (GridDirections.pos_x, GridDirections.pos_y, GridDirections.pos_z)
        1
    elseif dir in (GridDirections.neg_x, GridDirections.neg_y, GridDirections.neg_z)
        -1
    else
        error(dir)
    end
end

"Gets the grid direction indicated by the given rotation/forward vector"
function grid_dir(rot::fquat)::GridDirection
    return grid_dir(q_apply(rot, v3f(1, 0, 0)))
end
function grid_dir(forward::Vec3)::GridDirection
    axis = findmax(forward)[2]
    dir = sign(forward[axis])
    return (
        GridDirections.neg_x,
        GridDirections.neg_y,
        GridDirections.neg_z,
        GridDirections.pos_x,
        GridDirections.pos_y,
        GridDirections.pos_z
    )[axis + (3 * ((dir+1) ÷ 2))]
end

"Gets a vector pointing in the given direction"
function grid_vector(dir::GridDirection, ::Type{T} = Float32)::Vec{3, T} where {T}
    v = zero(Vec{3, T})
    @set! v[grid_axis(dir)] = convert(T, grid_sign(dir))
    return v
end