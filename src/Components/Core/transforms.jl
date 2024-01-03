##   WorldPosition   ##

#=
"
Something that exists in space, either discretely in the rock voxel grid or continuously.

If a specific subtype is not specified, the entity's position will be discrete by default.
"
=#
@component WorldPosition {abstract} {entitySingleton}  begin
    @promise get_voxel_position()::v3i
    @promise get_precise_position()::v3f
end
get_voxel_position(e::Entity)::v3i = get_component(e, WorldPosition).get_voxel_position()
get_precise_position(e::Entity)::v3f = get_component(e, WorldPosition).get_precise_position()


@component DiscretePosition <: WorldPosition begin
    pos::v3i

    get_voxel_position() = this.pos
    get_precise_position() = convert(v3f, this.pos)
end
@component ContinuousPosition <: WorldPosition begin
    pos::v3f

    get_voxel_position() = grid_idx(this.pos)
    get_precise_position() = this.pos
end


##   WorldOrientation   ##

@component WorldOrientation {entitySingleton} begin
    rot::fquat
    CONSTRUCT(rot = fquat()) = (this.rot = convert(fquat, rot))
end
get_orientation(e::Entity) = get_component(e, WorldOrientation).rot


##   Cosmetic Transform   ##

"Represents a temporary visual offset to position/orientation, in local space"
@component CosmeticOffset begin
    pos::v3f
    rot::fquat
    CONSTRUCT(pos = zero(v3f), rot = fquat()) = begin
        this.pos = convert(v3f, pos)
        this.rot = convert(fquat, rot)
    end
end
"Gets the cosmetic position of an entity, handling the case where the entity doesn't have a cosmetic offset"
function get_cosmetic_pos(e::Entity)
    pos = get_precise_position(e)
    for cosmetic::CosmeticOffset in get_components(e, CosmeticOffset)
        pos += cosmetic.pos
    end
    return pos
end

"Gets the cosmetic rotation of an entity, handling the case where the entity doesn't have a cosmetic offset"
function get_cosmetic_rot(e::Entity)
    rot::fquat = get_orientation(e)
    for cosmetic::CosmeticOffset in get_components(e, CosmeticOffset)
        rot <<= cosmetic.rot
    end
    return rot
end


##  Helper Functions  ##

"Gets the 4x4 world transform matrix for an entity that has position and orientation components"
get_world_transform(e::Entity) = get_world_transform(
    get_component(e, WorldPosition),
    get_component(e, WorldOrientation)
)
get_world_transform(p::WorldPosition,
                    o::WorldOrientation,
                    scale::v3f = one(v3f)) = m4_world(
    get_precise_position(p),
    o.rot,
    scale
)