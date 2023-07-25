# Cab position and movement/animation.

#######################
#  Movement animation

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
const CAB_SHAKE_MODES = Base.Callable[
    (t::Float32) -> CabShakeState(
        0.01 * v3f(
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
        @f32(π) * sin(t * PI2 *   99999) * 0.005,
        @f32(π) * sin(t * PI2 *  111111) * 0.005,
        @f32(π) * sin(t * PI2 * 3333333) * 0.005
    )
]
const NShakeModes = length(CAB_SHAKE_MODES)

"A specific moment of the player's movement animation"
struct CabMovementKeyframe
    delta_pos::v3f
    t::Float32
    shake_strengths::NTuple{NShakeModes, Float32}
end


"
One of the pre-programmed movements the player can make under certain conditions.
Assumes forward is +X, rightward is +Y, and upward is +Z (left-handed coordinates).
"
struct CabMovement
    time_seconds::Float32
    keyframes::Vector{CabMovementKeyframe} # Each keyframe position must be empty of rock
                                           #    for the move to be legal.
    solid_surfaces::Vector{v3i} # Grid cells (relative to the player) that must be solid
                                #    for the move to be legal.
                                # Cells outside the level bounds are considered solid.
end
const LEGAL_MOVES = (let CMKf = CabMovementKeyframe
    [
        # Move forward on treads.
        CabMovement(
            3.0,
            [
                CMKf(v3f(0, 0, 0), 0.02,
                     (1, 0)),

                CMKf(v3f(0.5, 0, 0), 0.65,
                     (0.8, 0.2)),

                CMKf(v3f(1, 0, 0), 0.98,
                     (1, 0)),
                CMKf(v3f(1, 0, 0), 1.0,
                     (0, 0))
            ],
            [
                v3i(0, 0, -1),
                v3i(1, 0, -1)
            ]
        ),

        # Climb up over a corner.
        CabMovement(
            5.0,
            [
                CMKf(v3f(0, 0, 0), 0.02,
                     (1, 0)),
                CMKf(v3f(0.35, 0, 0), 0.3,
                     (1, 0)),

                CMKf(v3f(0.35, 0, 0.4), 0.49,
                     (0, 0)),
                CMKf(v3f(0.35, 0, 0.4), 0.5,
                     (0, 1)),

                CMKf(v3f(0.75, 0, 0.75), 0.85,
                     (0, 1)),

                CMKf(v3f(1, 0, 1), 1.0,
                     (0, 0))
            ],
            [
                v3i(0, 0, -1),
                v3i(1, 0, 0)
            ]
        ),

        # Climb down across a corner.
        CabMovement(
            6.0,
            [
                CMKf(v3f(0, 0, 0), 0.02,
                     (1, 0)),
                CMKf(v3f(0.35, 0, 0), 0.2,
                     (1, 0)),

                CMKf(v3f(0.5, 0, 0), 0.6,
                     (0, 0)),

                CMKf(v3f(0.5, 0, 0), 0.61,
                     (1, 1)),
                CMKf(v3f(0.6, 0, -1), 0.7,
                     (2, 0.5)),

                CMKf(v3f(1, 0, -1), 0.98,
                     (0.8, 0.1)),
                CMKf(v3f(1, 0, -1), 1.0,
                     (0, 0))
            ],
            [
                v3i(0, 0, -1),
                v3i(1, 0, -2)
            ]
        )
    ]
end)
# Check that the movement keyframes are well-ordered.
for (move_idx, move) in enumerate(LEGAL_MOVES)
    for key_idx in 2:length(move.keyframes)
        prev_key = move.keyframes[key_idx - 1]
        next_key = move.keyframes[key_idx]
        @bp_check(prev_key.t < next_key.t,
                  "Invalid animation keyframes! In move ", move_idx,
                    ", keyframe ", key_idx-1, " does not come before keyframe ", key_idx)
    end
end


"The different horizontal configurations of a player movement"
struct CabMovementDir
    axis::UInt8 # Forward direction: 1 for X, 2 for Y
    dir::Int8 # Forward direction: -1 for backwards, +1 for forwards, along 'axis'
    flip::Int8 # Sideways direction: -1 for left, 1 for right
end

const ALL_MOVEMENT_DIRS = collect(
    CabMovementDir(axis, dir, flip)
      for axis in (1, 2)
      for dir in (-1, +1)
      for flip in (-1, +1)
)

"Transforms a cab movement vector from its canonical direction into the given direction"
function rotate_cab_movement(v::Vec3, dir::CabMovementDir)::typeof(v)
    right_axis = mod1(dir.axis + 1, 2)
    return Vec(
        dir.dir * v[dir.axis],
        dir.flip * v[right_axis],
        v[3]
    )
end

"
Checks if a movement is legal.
The forward direction of movement is specified as an 'axis' of 1 or 2, and a 'direction' of -1 or +1.
"
function is_legal(move::CabMovement, dir::CabMovementDir,
                  start_grid_pos::v3i, grid::RockGrid)::Bool
    grid_idx_range = Box3Di(min=one(v3i), max=vsize(grid))
    is_free(grid_idx) = is_touching(grid_idx_range, grid_idx) && (grid[grid_idx] == RockTypes.empty)

    # All keyframed positions should occupy empty space.
    for key::CabMovementKeyframe in move.keyframes
        grid_pos_f = start_grid_pos + rotate_cab_movement(key.delta_pos, dir)
        grid_pos = rock_grid_idx(grid_pos_f)
        if !is_free(grid_pos)
            return false
        end
    end

    # All explicit 'solid' positions should be solid.
    for offset in move.solid_surfaces
        grid_pos = start_grid_pos + rotate_cab_movement(offset, dir)
        if is_free(grid_pos)
            return false
        end
    end

    return true
end


########################
#  Movement simulation

mutable struct CabMovementState
    pos::v3f # Relative to player's starting pos
    shake_strengths::NTuple{NShakeModes, Float32}
    t::Float32
    key_idx::Int

    src::CabMovement
    heading::CabMovementDir

    CabMovementState(src::CabMovement, heading::CabMovementDir) = new(
        zero(v3f),
        ntuple(i -> zero(Float32), Val(NShakeModes)),
        zero(Float32),
        one(Int),

        src,
        heading
    )
end

"Updates the Cab movement's state and returns whether it's complete"
function update_movement!(cms::CabMovementState, delta_seconds::Float32)::Bool
    local prev_key::CabMovementKeyframe
    if cms.key_idx == 1
        prev_key = CabMovementKeyframe(zero(v3f), zero(Float32),
                                       ntuple(i->zero(Float32), Val(NShakeModes)))
    else
        prev_key = cms.src.keyframes[cms.key_idx - 1]
    end

    next_key = cms.src.keyframes[cms.key_idx]

    # Apply the heading to the keyframes.
    @set! prev_key.delta_pos = rotate_cab_movement(prev_key.delta_pos, cms.heading)
    @set! next_key.delta_pos = rotate_cab_movement(next_key.delta_pos, cms.heading)

    # If this frame would go past the current keyframe, cut it off at that keyframe
    #    and make a recursive call to process the next one.
    time_to_next_keyframe = (next_key.t - cms.t) * cms.src.time_seconds
    passes_keyframe::Bool = time_to_next_keyframe <= delta_seconds
    capped_delta_seconds = passes_keyframe ? time_to_next_keyframe : delta_seconds

    cms.t += capped_delta_seconds / cms.src.time_seconds

    # Update the position, or move on to the next keyframe if time is left.
    if passes_keyframe
        # If there are no keyframes left, the animation is finished.
        if cms.key_idx == length(cms.src.keyframes)
            cms.pos = next_key.delta_pos
            cms.shake_strengths = next_key.shake_strengths
            return true
        else
            cms.key_idx += 1
            return update_movement!(cms, delta_seconds - time_to_next_keyframe)
        end
    else
        frame_t::Float32 = inv_lerp(prev_key.t, next_key.t, cms.t)
        cms.pos = lerp(prev_key.delta_pos, next_key.delta_pos, frame_t)
        cms.shake_strengths = ntuple(
            i -> lerp(prev_key.shake_strengths[i],
                      next_key.shake_strengths[i],
                      frame_t),
            Val(NShakeModes)
        )
        return false
    end
end


##################
#  Overall state

mutable struct CabState
    grid_pos::v3f # Not including any ongoing movement animation.
    current_movement::Optional{CabMovementState}

    facing_dir::v3f # Always normalized
end

"Gets the view position and direction of the given cab, taking animation into account"
function get_cab_view(cab::CabState, elapsed_seconds::Float32)::@NamedTuple{pos::v3f, forward::v3f}
    pos = cab.grid_pos
    forward = cab.facing_dir

    # Apply position offset from movement animation.
    if exists(cab.current_movement)
        pos += cab.current_movement.pos

        # Apply camera shake.
        basis = vbasis(cab.facing_dir)
        for shake_idx in 1:NShakeModes
            shake::CabShakeState = CAB_SHAKE_MODES[shake_idx](elapsed_seconds)
            strength = cab.current_movement.shake_strengths[shake_idx]

            pos += shake.pos * strength
            forward = q_apply(fquat(basis.up, shake.yaw * strength), forward)
            forward = q_apply(fquat(basis.right, shake.pitch * strength), forward)
            forward = q_apply(fquat(basis.forward, shake.roll * strength), forward)
        end
    end

    return (pos=pos, forward=forward)
end

function update_cab!(cab::CabState, delta_seconds::Float32)
    if exists(cab.current_movement)
        is_done = update_movement!(cab.current_movement, delta_seconds)
        if is_done
            cab.grid_pos += cab.current_movement.pos
            cab.current_movement = nothing
        end
    end

    return nothing
end