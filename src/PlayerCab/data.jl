"
The player's available cab features, based on what choices/purchases they made.
During a mission, it can get modified.

By default, generates the base loadout for a brand new pod (no upgrades).

Copy it with `Base.copy()`.
"
Base.@kwdef mutable struct PlayerLoadout
    braces_after_drilling::Bool = false
    can_climb::Bool = false
    can_cross_gaps::Bool = false
end
Base.copy(pl::PlayerLoadout) = PlayerLoadout((
    getfield(pl, f) for f in fieldnames(PlayerLoadout)
)...)

"Generates a souped-up loadout for debugging"
maxed_loadout() = PlayerLoadout(
    braces_after_drilling = true,
    can_climb = true,
    can_cross_gaps = true
)


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

const GLOBAL_SHAKE_STRENGTH = 0.0025

"
Different ways the cab can shake.
Each method is a function mapping a time value to a `CabShakeState`.
"
const CAB_SHAKE_MODES = tuple(
    (t::Float32) -> CabShakeState(
        GLOBAL_SHAKE_STRENGTH * v3f(
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
        @f32(π) * sin(t * PI2 *   99999) * GLOBAL_SHAKE_STRENGTH,
        @f32(π) * sin(t * PI2 *  111111) * GLOBAL_SHAKE_STRENGTH,
        @f32(π) * sin(t * PI2 * 3333333) * GLOBAL_SHAKE_STRENGTH
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


# Short-hands for move definitions

const MOVE_FORWARD, MOVE_BACKWARD,
      MOVE_LEFT, MOVE_RIGHT,
      MOVE_CLIMB_UP, MOVE_CLIMB_DOWN,
      MOVE_GAP_FORWARD, MOVE_GAP_LEFT, MOVE_GAP_RIGHT = let CMKf = CabMovementKeyframe,
                                                            SV = Vec{N_SHAKE_MODES, Float32}
    [
        # Forward
        CabMovementData(
            2.0,
            [
                CMKf(v3f(0, 0, 0), 0.02,
                    SV(1, 0)),

                CMKf(v3f(0.5, 0, 0), 0.65,
                    SV(0.8, 0.2)),

                CMKf(v3f(1, 0, 0), 0.98,
                    SV(1, 0)),
                CMKf(v3f(1, 0, 0), 1.0,
                    SV(0, 0))
            ],
            [
                # v3i(0, 0, -1),
                # v3i(1, 0, -1)
            ],
            false
        ),
        # Backward
        CabMovementData(
            2.0,
            [
                CMKf(v3f(0, 0, 0), 0.02,
                    SV(1, 0)),

                CMKf(v3f(-0.5, 0, 0), 0.65,
                    SV(0.8, 0.2)),

                CMKf(v3f(-1, 0, 0), 0.98,
                    SV(1, 0)),
                CMKf(v3f(-1, 0, 0), 1.0,
                    SV(0, 0))
            ],
            [
                # v3i(0, 0, -1),
                # v3i(-1, 0, -1)
            ],
            false
        ),

        # Left
        CabMovementData(
            2.0,
            [
                CMKf(v3f(0, 0, 0), 0.02,
                    SV(1, 0)),

                CMKf(v3f(0, -0.5, 0), 0.65,
                    SV(0.8, 0.2)),

                CMKf(v3f(0, -1, 0), 0.98,
                    SV(1, 0)),
                CMKf(v3f(0, -1, 0), 1.0,
                    SV(0, 0))
            ],
            [
                # v3i(0, 0, -1),
                # v3i(0, -1, -1)
            ],
            false
        ),

        # Right
        CabMovementData(
            2.0,
            [
                CMKf(v3f(0, 0, 0), 0.02,
                    SV(1, 0)),

                CMKf(v3f(0, 0.5, 0), 0.65,
                    SV(0.8, 0.2)),

                CMKf(v3f(0, 1, 0), 0.98,
                    SV(1, 0)),
                CMKf(v3f(0, 1, 0), 1.0,
                    SV(0, 0))
            ],
            [
                # v3i(0, 0, -1),
                # v3i(0, 1, -1)
            ],
            false
        ),

        # Climb up
        CabMovementData(
            2.0,
            [
                CMKf(v3f(0, 0, 0), 0.02,
                    SV(1, 0)),
                CMKf(v3f(0.35, 0, 0), 0.3,
                    SV(1, 0)),

                CMKf(v3f(0.35, 0, 0.4), 0.49,
                    SV(0, 0)),
                CMKf(v3f(0.35, 0, 0.4), 0.5,
                    SV(0, 1)),

                CMKf(v3f(0.65, 0, 0.75), 0.85,
                    SV(0, 1)),

                CMKf(v3f(1, 0, 1), 1.0,
                    SV(0, 0))
            ],
            [
                v3i(0, 0, -1),
                v3i(1, 0, 0)
            ],
            false
        ),
        # Climb down:
        CabMovementData(
            2.0,
            [
                CMKf(v3f(0, 0, 0), 0.02,
                    SV(1, 0)),
                CMKf(v3f(0.35, 0, 0), 0.2,
                    SV(1, 0)),

                CMKf(v3f(0.5, 0, 0), 0.6,
                    SV(0, 0)),

                CMKf(v3f(0.5, 0, 0), 0.61,
                    SV(1, 1)),
                CMKf(v3f(0.6, 0, -1), 0.7,
                    SV(2, 0.5)),

                CMKf(v3f(1, 0, -1), 0.98,
                    SV(0.8, 0.1)),
                CMKf(v3f(1, 0, -1), 1.0,
                    SV(0, 0))
            ],
            [
                v3i(0, 0, -1),
                v3i(1, 0, -2)
            ],
            false
        ),

        # Gap forward:
        CabMovementData(
            3.0,
            [
                CMKf(v3f(0, 0, 0), 0.05,
                     SV(0.25, 0)),
                CMKf(v3f(0.35, 0, 0), 0.2,
                     SV(0.5, 0)),
                CMKf(v3f(0.5, 0, 0), 0.24,
                     SV(0.25, 0)),

                CMKf(v3f(1.5, 0, 0), 0.35,
                     SV(1, 0)),
                CMKf(v3f(1.5, 0, 0), 0.85,
                     SV(1, 0)),
                CMKf(v3f(1.5, 0, 0), 0.95,
                     SV(0.25, 0)),

                CMKf(v3f(2, 0, 0), 1.0,
                     SV(0, 0))
            ],
            [
                # v3i(0, 0, -1),
                # v3i(2, 0, -1)
            ],
            false
        ),
        # Gap left:
        CabMovementData(
            3.0,
            [
                CMKf(v3f(0, 0, 0), 0.05,
                     SV(0.25, 0)),
                CMKf(v3f(0.35, 0, 0), 0.2,
                     SV(0.5, 0)),
                CMKf(v3f(0.5, 0, 0), 0.24,
                     SV(0.25, 0)),

                CMKf(v3f(0.75, -0.25, 0), 0.35,
                     SV(1, 0)),
                CMKf(v3f(0.95, -0.75, 0), 0.85,
                     SV(1, 0)),
                CMKf(v3f(1, -0.9, 0), 0.95,
                     SV(0.25, 0)),

                CMKf(v3f(1, -1, 0), 1.0,
                     SV(0, 0))
            ],
            [
                # v3i(0, 0, -1),
                # v3i(1, -1, -1)
            ],
            false
        ),
        # Gap right:
        CabMovementData(
            3.0,
            [
                CMKf(v3f(0, 0, 0), 0.05,
                     SV(0.25, 0)),
                CMKf(v3f(0.35, 0, 0), 0.2,
                     SV(0.5, 0)),
                CMKf(v3f(0.5, 0, 0), 0.24,
                     SV(0.25, 0)),

                CMKf(v3f(0.75, 0.25, 0), 0.35,
                     SV(1, 0)),
                CMKf(v3f(0.95, 0.75, 0), 0.85,
                     SV(1, 0)),
                CMKf(v3f(1, 0.9, 0), 0.95,
                     SV(0.25, 0)),

                CMKf(v3f(1, 1, 0), 1.0,
                     SV(0, 0))
            ],
            [
                # v3i(0, 0, -1),
                # v3i(1, 1, -1)
            ],
            false
        ),
    ]
end
# Check that the movement keyframes are well-ordered.
for (move_name, move) in [ ("MOVE_FORWARD", MOVE_FORWARD), ("MOVE_BACKWARD", MOVE_BACKWARD),
                           ("MOVE_LEFT", MOVE_LEFT), ("MOVE_RIGHT", MOVE_RIGHT),
                           ("MOVE_CLIMB_UP", MOVE_CLIMB_UP), ("MOVE_CLIMB_DOWN", MOVE_CLIMB_DOWN) ]
    for key_idx in 2:length(move.keyframes)
        prev_key = move.keyframes[key_idx - 1]
        next_key = move.keyframes[key_idx]
        @bp_check(prev_key.t < next_key.t,
                  "Invalid animation keyframes! In move ", move_name,
                    ", keyframe ", key_idx-1, " does not come before keyframe ", key_idx)
    end
end


########################
#  Turning simulation

const TURN_INCREMENT_DEG = @f32(30)


########################
#  Drilling simulation

const DRILL_DURATION_SECONDS = @f32(2)
const DRILL_SHAKE_STRENGTH = @f32(1)

const DRILL_PROGRESS_CURVE = Curve{Float32}(
    CurveKey(v2f(0, 0),
             CurveLinearSlope()),
    CurveKey(v2f(0.8, 0.15),
             CurveLinearSlope()),
    CurveKey(v2f(0.9, 0.95),
             CurveExponentialSlope(0.8)),
    CurveKey(v2f(1.0, 1.0)),

    perlin_settings=CurvePerlin(
        0.025, 0.01,
        0.1, 2.0
    )
)