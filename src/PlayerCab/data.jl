"
The player's available cab features, based on what choices/purchases they made.
During a mission, it can get modified.

Copy it with `Base.copy()`.
"
Base.@kwdef mutable struct PlayerLoadout
    braces_after_drilling::Bool = false
end
Base.copy(pl::PlayerLoadout) = PlayerLoadout((
    getfield(pl, f) for f in fieldnames(PlayerLoadout)
)...)

#######################
#  Cab state

ECS.@component Cab {entitySingleton} {require: ContinuousPosition, WorldOrientation} begin
    # If true, this cab is bracing itself to prevent falling when there is no floor underneath it.
    is_bracing::Bool
    loadout::PlayerLoadout
    pos_component::ContinuousPosition
    rot_component::WorldOrientation

    function CONSTRUCT(initial_loadout::PlayerLoadout)
        this.is_bracing = false
        this.loadout = copy(initial_loadout)
        this.pos_component = get_component(entity, ContinuousPosition)
        this.rot_component = get_component(entity, WorldOrientation)
    end
    function DESTRUCT(is_entity_dying::Bool)
        if !is_entity_dying
            @warn "Cab component is being destroyed early for some reason"
        end
    end
end


#######################
#  Shake

"A transform offset due to shaking FX. Angles are in radians."
struct CabShakeState
    pos::v3f
    pitch::Float32
    yaw::Float32
    roll::Float32
end

"
Different ways the cab can shake.
Each method is a function mapping a time value to a `CabShakeState`.
"
const CAB_SHAKE_MODES = tuple(
    (t::Float32) -> CabShakeState(
        0.02 * v3f(
            sin(t * PI2 * 99999),
            cos(t * PI2 * 999999),
            0
        ),
        # No rotational shake in this mode.
        zero(Float32),
        zero(Float32),
        zero(Float32)
    ),
    (t::Float32) -> CabShakeState(
        # No positional shake in this mode.
        zero(v3f),
        @f32(π) * sin(t * PI2 *   99999) * 0.02,
        @f32(π) * sin(t * PI2 *  111111) * 0.02,
        @f32(π) * sin(t * PI2 * 3333333) * 0.02
    )
)
const N_SHAKE_MODES = length(CAB_SHAKE_MODES)


#######################
#  Movement Animations

# Cab movements are defined in a canonical direction, using left-handed coordinates:
#    +X is forward
#    +Y is rightward
#    +Z is upward

"A specific moment of the player's movement animation"
struct CabMovementKeyframe
    delta_pos::v3f
    t::Float32
    shake_strengths::VecF{N_SHAKE_MODES}
end

"
One of the pre-programmed movements the player can make under certain conditions.
Uses canonical cab directions (forward is +X, rightward is +Y, and upward is +Z.
"
struct CabMovementData
    time_seconds::Float32
    keyframes::Vector{CabMovementKeyframe} # Each keyframe position must be empty of rock
                                           #    for the move to be legal.
    solid_surfaces::Vector{v3i} # Grid cells (relative to the player) that must be solid
                                #    for the move to be legal.
                                # Cells outside the level bounds are considered solid.
    braces_at_end::Bool # Whether the player can hold themselves in the air at the end of the movement.
                        # If false, and they end on empty space, they'll fall down.
end


#######################
#  Movement WorldOrientation

struct CabMovementDir
    grid::GridDirection
    flip::Int8 # Sideways direction: -1 for left, +1 for right
end

const ALL_MOVEMENT_DIRS = Tuple(
    CabMovementDir(grid, flip)
      for grid in GridDirections.instances()
      for flip in (-1, +1)
)

"
Transforms a cab movement vector/coordinate from its canonical coordinate space
into physical space, given a specific orientation.
Assumes the orientation is horizontal.
"
function rotate_cab_movement(v::Vec3, dir::CabMovementDir)::typeof(v)
    axis = grid_axis(dir.grid)
    sign = grid_sign(dir.grid)
    @bp_check(axis in 1:2,
              "Cab oriented along vertical axis?? ", dir, " => ", axis, "|", sign)
    return Vec(
        if axis == 1
            sign * v.x
        else
            dir.flip * sign * v.y
        end,
        if axis == 2
            sign * v.x
        else
            dir.flip * -sign * v.y
        end,
        v[3]
    )
end


########################
#  Movement simulation

"
Checks if a movement is legal.
The forward direction of movement is specified as an 'axis' of 1 or 2, and a 'direction' of -1 or +1.
"
function is_legal(move::CabMovementData, dir::CabMovementDir,
                  start_grid_pos::v3i,
                  is_free::Base.Callable # (grid_idx::Vec3) -> Bool
                 )
    # All keyframed positions should occupy empty space.
    for key::CabMovementKeyframe in move.keyframes
        grid_pos_f = start_grid_pos + rotate_cab_movement(key.delta_pos, dir)
        grid_position = grid_idx(grid_pos_f)
        if !is_free(grid_position)
            return false
        end
    end

    # All explicit 'solid' positions should be solid.
    for offset in move.solid_surfaces
        grid_position = start_grid_pos + rotate_cab_movement(offset, dir)
        if is_free(grid_position)
            return false
        end
    end

    return true
end


########################
#  Drilling simulation


const DRILL_DURATION_SECONDS = @f32(2)

const DRILL_SHAKE_STRENGTH = @f32(1)