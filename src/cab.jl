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
]
const NShakeModes = length(CAB_SHAKE_MODES)

"A specific moment of the player's movement animation"
struct CabMovementKeyframe
    delta_pos::v3f
    t::Float32
    shake_strengths::VecF{NShakeModes}
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
const LEGAL_MOVES = (let CMKf = CabMovementKeyframe,
                         SV = Vec{NShakeModes, Float32}
    [
        # Move forward on treads.
        CabMovement(
            3.0,
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
                v3i(0, 0, -1),
                v3i(1, 0, -1)
            ]
        ),

        # Climb up over a corner.
        CabMovement(
            5.0,
            [
                CMKf(v3f(0, 0, 0), 0.02,
                     SV(1, 0)),
                CMKf(v3f(0.35, 0, 0), 0.3,
                     SV(1, 0)),

                CMKf(v3f(0.35, 0, 0.4), 0.49,
                     SV(0, 0)),
                CMKf(v3f(0.35, 0, 0.4), 0.5,
                     SV(0, 1)),

                CMKf(v3f(0.75, 0, 0.75), 0.85,
                     SV(0, 1)),

                CMKf(v3f(1, 0, 1), 1.0,
                     SV(0, 0))
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
        if dir.axis == 1
            dir.dir * v.x
        else
            dir.flip * dir.dir * v.y
        end,
        if dir.axis == 2
            dir.dir * v.x
        else
            dir.flip * dir.dir * v.y
        end,
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
        CImGui.Text("\tKeyframe pos $grid_pos\n\t\t(from $grid_pos_f) is $(is_free(grid_pos) ? "" : "not ") free\n\t\tSource: $(key.delta_pos)\n\t\tBecomes: $(rotate_cab_movement(key.delta_pos, dir))")
        if !is_free(grid_pos)
            return false
        end
    end

    # All explicit 'solid' positions should be solid.
    for offset in move.solid_surfaces
        grid_pos = start_grid_pos + rotate_cab_movement(offset, dir)
        CImGui.Text("\tWall pos $grid_pos\n\t\t(from $start_grid_pos + rot($offset))\n\t\tis $(is_free(grid_pos) ? "" : "not ") free")
        if is_free(grid_pos)
            return false
        end
    end

    return true
end


########################
#  Movement simulation

mutable struct CabMovementState
    pos::v3f # Relative to player's pos at the start of the movement
    shake_strengths::Vec{NShakeModes, Float32}
    t::Float32
    key_idx::Int

    src::CabMovement
    heading::CabMovementDir

    CabMovementState(src::CabMovement, heading::CabMovementDir) = new(
        zero(v3f),
        zero(Vec{NShakeModes, Float32}),
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
                                       zero(Vec{NShakeModes, Float32}))
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
        cms.shake_strengths = lerp(prev_key.shake_strengths, next_key.shake_strengths, frame_t)
        return false
    end
end


########################
#  Drilling simulation

struct DrillDirection
    axis::UInt8 # 1, 2, or 3
    side::Int8 # -1 or +1
end

mutable struct CabDrillState
    dir::DrillDirection
    seed::Float32 # Constant random value from 0 to 1

    pos::v3f # Relative to the cab position at the start of the drill movement
    t::Float32 # Animation progress from 0 to 1

    CabDrillState(dir, seed) = new(dir, seed, zero(v3f), zero(Float32))
end

const DRILL_DURATION_SECONDS = @f32(3)

"Updates the Cab drill's state and returns whether it's finished drilling"
function update_drill!(cds::CabDrillState, delta_seconds::Float32)::Bool
    # Move forward in time.
    cds.t += delta_seconds / DRILL_DURATION_SECONDS
    cds.t = min(1, cds.t)

    # Move forward in space.
    cds.pos = cds.t * v3f(i -> (i == cds.dir.axis) ? cds.dir.side : 0)

    # Animation is over when t reaches 1.0.
    return cds.t >= 1
end

const DRILL_SHAKE_STRENGTH = @f32(1)

function drill_shake_strengths(cds::CabDrillState,
                               elapsed_seconds::Float32)::Vec{NShakeModes, Float32}
    # Shake strength should fade in and out.
    window = @f32(sin(cds.t * π) ^ 0.15)

    # It should be randomly distributed among the possible shake types.
    # I'm not sure how to perfectly distribute continuous numbers,
    #    but distributing discrete elements is easy.
    output = zero(Vec{NShakeModes, Float32})
    N_SEGMENTS = 10
    rng = ConstPRNG(cds.seed)
    for i in 1:N_SEGMENTS
        bucket = rand(rng, 1:NShakeModes)
        @set! output[bucket] += @f32(1 / N_SEGMENTS)
    end

    return output
end


##################
#  Overall state

mutable struct CabState
    grid_pos::v3f # Not including any ongoing movement animation.
    current_action::Union{CabMovementState, CabDrillState, Nothing}

    facing_dir::v3f # Always normalized
end

"Gets the view position and direction of the given cab, taking animation into account"
function get_cab_view(cab::CabState, elapsed_seconds::Float32)::@NamedTuple{pos::v3f, forward::v3f}
    basis = vbasis(cab.facing_dir)

    final_pos = cab.grid_pos
    final_forward = cab.facing_dir

    # Define shaking's effect on the camera.
    cab_shake_values = Vec{NShakeModes, CabShakeState}(i -> CAB_SHAKE_MODES[i](elapsed_seconds))
    function apply_cam_shake(shake_idx::Int, strength::Float32)
        shake = cab_shake_values[shake_idx]
        final_pos += shake.pos * strength
        final_forward = q_apply(fquat(basis.up, shake.yaw * strength), final_forward)
        final_forward = q_apply(fquat(basis.right, shake.pitch * strength), final_forward)
        final_forward = q_apply(fquat(basis.forward, shake.roll * strength), final_forward)
    end
    function apply_cam_shake(strengths::Vec{NShakeModes, Float32})
        for (i, strength) in enumerate(strengths)
            apply_cam_shake(i, strength)
        end
    end

    # Apply movement animation.
    if cab.current_action isa CabMovementState
        final_pos += cab.current_action.pos
        apply_cam_shake(cab.current_action.shake_strengths)
    elseif cab.current_action isa CabDrillState
        pos += cab.current_action.pos
        apply_cam_shake(drill_shake_strengths(cab.current_action, elapsed_seconds))
    end

    return (pos=final_pos, forward=final_forward)
end

function update_cab!(cab::CabState, rock_grid::RockGrid, delta_seconds::Float32)
    if cab.current_action isa CabMovementState
        is_done = update_movement!(cab.current_action, delta_seconds)
        if is_done
            cab.grid_pos += cab.current_action.pos
            cab.current_action = nothing
        end
    elseif cab.current_action isa CabDrillState
        is_done = update_drill!(cab.current_action, delta_seconds)
        if is_done
            cab.grid_pos += caab.current_action.pos

            grid_pos = rock_grid_idx(cab.grid_pos)
            drilled_rock = rock_grid[grid_pos]
            @bp_check(drilled_rock != RockTypes.empty,
                      "Drilled into empty rock at ", grid_pos)
            rock_grid[grid_pos] = RockTypes.empty

            cab.current_action = nothing
        end
    end

    return nothing
end