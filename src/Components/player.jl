const TURN_SPEED_DEG_PER_SECOND = 180
const TURN_INCREMENT_DEG = 30


##   Maneuvers   ##

abstract type AbstractManeuverComponent <: AbstractComponent end
ECS.require_components(::Type{<:AbstractManeuverComponent}) = (ContinuousPosition, )
ECS.allow_multiple(::Type{<:AbstractManeuverComponent}) = false

"Sets a cosmetic position/rotation offset based on cab shaking effects"
function calculate_shake(elapsed_seconds::Float32,
                         shake_strengths::Vec{NShakeModes, Float32},
                         output::CosmeticOffsetComponent)
    cab_shake_states = Vec{NShakeModes, CabShakeState}(
        i -> CAB_SHAKE_MODES[i](elapsed_seconds)
    )
    output.pos = sum(
        state.pos * strength
        for (state, strength) in zip(cab_shake_states, shake_strengths)
    )
    output.rot = let rot = fquat()
        for (state, strength) in zip(cab_shake_states, shake_strengths)
            rot >>= fquat(get_up_vector(), state.yaw * strength)
            rot >>= fquat(get_horz_vector(2), state.pitch * strength)
            rot >>= fquat(get_horz_vector(1), state.roll * strength)
        end
        rot
    end
end


##   Turning   ##

"Manages a cab's turning motion. Pass `target` when creating it."
mutable struct CabTurnComponent <: AbstractManeuverComponent
    cosmetic_shake::CosmeticOffsetComponent
    target::fquat
end

function ECS.create_component(::Type{CabTurnComponent}, entity::Entity,
                              target::fquat)
    @bp_check(!has_component(entity, AbstractManeuverComponent),
              "Entity is already in the middle of a maneuver")
    return CabTurnComponent(
        add_component(CosmeticOffsetComponent, entity),
        target
    )
end
function ECS.destroy_component(cab_turn::CabTurnComponent,
                               entity::Entity,
                               is_dying::Bool)
    if !is_dying
        remove_component(cab_turn.cosmetic_shake, entity)
    end
end

function ECS.tick_component(cab_turn::CabTurnComponent,
                            entity::Entity,
                            rot_component::OrientationComponent = get_component(entity, OrientationComponent))
    # Calculate the full turn needed to make it to the target.
    forward::v3f = q_apply(rot_component.rot, get_horz_vector(1))
    desired_forward::v3f = q_apply(cab_turn.target, get_horz_vector(1))
    full_turn = fquat(forward, desired_forward)
    (turn_axis, turn_radians) = q_axisangle(full_turn)

    # Constrain the turn based on the size of the time-step.
    delta_seconds::Float32 = entity.world.delta_seconds
    frame_max_rad = deg2rad(delta_seconds * TURN_SPEED_DEG_PER_SECOND)
    is_finishing_turn::Bool = (frame_max_rad >= abs(turn_radians))

    # Apply the turn movement.
    if is_finishing_turn
        rot_component.rot = cab_turn.target
        remove_component(cab_turn, entity)
    else
        rot_component.rot >>= fquat(turn_axis, copysign(frame_max_rad, turn_radians))
    end

    return nothing
end


##   Movement   ##

"Manages a Cab movement. Pass `src` and `heading` when creating it."
mutable struct CabMovementComponent <: AbstractManeuverComponent
    cosmetic_shake::CosmeticOffsetComponent
    original_pos::v3f

    t::Float32
    key_idx::Int

    src::CabMovement
    heading::CabMovementDir
end

function ECS.create_component(::Type{CabMovementComponent}, entity::Entity,
                              src::CabMovement, heading::CabMovementDir)
    @bp_check(!has_component(entity, AbstractManeuverComponent),
              "Entity is already in the middle of a maneuver")
    return CabMovementComponent(
        add_component(entity, CosmeticOffsetComponent),
        get_precise_position(entity),
        zero(Float32),
        one(Int),
        src, heading
    )
end
function ECS.destroy_component(cab_movement::CabMovementComponent,
                               entity::Entity,
                               is_dying::Bool)
    if !is_dying
        remove_component(cab_movement.cosmetic_shake, entity)
    end
end

function ECS.tick_component(cab_movement::CabMovementComponent, entity::Entity,
                            delta_seconds::Float32 = entity.world.delta_seconds,
                            pos_component::ContinuousPosition = get_component(entity, ContinuousPosition))
    # Get the previous animation key, or a stand-in if we're at the first key.
    local prev_key::CabMovementKeyframe
    if cab_movement.key_idx == 1
        prev_key = CabMovementKeyframe(zero(v3f), zero(Float32),
                                       zero(Vec{NShakeModes, Float32}))
    else
        prev_key = cab_movement.src.keyframes[cab_movement.key_idx - 1]
    end

    next_key = cab_movement.src.keyframes[cab_movement.key_idx]

    # Apply the heading to the keyframes.
    @set! prev_key.delta_pos = rotate_cab_movement(prev_key.delta_pos, cab_movement.heading)
    @set! next_key.delta_pos = rotate_cab_movement(next_key.delta_pos, cab_movement.heading)

    # If this frame would go past the current keyframe, cut it off at that keyframe
    #    and make a recursive call to process the next one.
    time_to_next_keyframe = (next_key.t - cab_movement.t) * cab_movement.src.time_seconds
    passes_keyframe::Bool = time_to_next_keyframe <= delta_seconds
    capped_delta_seconds = passes_keyframe ? time_to_next_keyframe : delta_seconds

    cab_movement.t += capped_delta_seconds / cab_movement.src.time_seconds

    # Update the position, or move on to the next keyframe if time is left.
    if passes_keyframe
        # If there are no keyframes left, the animation is finished.
        if cab_movement.key_idx == length(cab_movement.src.keyframes)
            pos_component.pos = cab_movement.original_pos + next_key.delta_pos
            remove_component(cab_movement, entity)
        else
            cab_movement.key_idx += 1
            tick_component(cab_movement, entity,
                           delta_seconds - time_to_next_keyframe,
                           pos_component)
        end
    else
        frame_t::Float32 = inv_lerp(prev_key.t, next_key.t, cab_movement.t)
        pos_component.pos = cab_movement.original_pos +
                            lerp(prev_key.delta_pos, next_key.delta_pos, frame_t)
        shake_strengths = lerp(prev_key.shake_strengths,
                               next_key.shake_strengths,
                               frame_t)

        calculate_shake(entity.world.elapsed_seconds,
                        shake_strengths,
                        cab_movement.cosmetic_shake)
    end

    return nothing
end


##   Drilling   ##

mutable struct CabDrillComponent <: AbstractComponent
    cosmetic_shake::CosmeticOffsetComponent
    original_pos::v3f

    dir::GridDirection
    rng_seed::Float32

    t::Float32
end

function ECS.create_component(::Type{CabDrillComponent}, entity::Entity,
                              dir::GridDirection, rng_seed::Float32)
    @bp_check(!has_component(entity, AbstractManeuverComponent),
              "Entity is already in the middle of a maneuver")
    return CabDrillComponent(
        add_component(entity, CosmeticOffsetComponent),
        get_precise_position(entity),
        dir,
        rng_seed,
        zero(Float32)
    )
end
function ECS.destroy_component(cab_drill::CabDrillComponent,
                               entity::Entity,
                               is_dying::Bool)
    if !is_dying
        remove_component(cab_drill.cosmetic_shake, entity)
    end
end

function ECS.tick_component(cab_drill::CabDrillComponent, entity::Entity,
                            delta_seconds::Float32 = entity.world.delta_seconds,
                            pos_component::ContinuousPosition = get_component(entity, ContinuousPosition))
    # Move forward in time.
    cab_drill.t += delta_seconds / DRILL_DURATION_SECONDS
    cab_drill.t = min(1, cab_drill.t)
    if cab_drill.t >= 1
        remove_component(cab_drill, entity)
        return nothing
    end

    # Move forward in space.
    pos_component.pos = cab_drill.original_pos +
                        let movement = zero(v3f)
                            axis = grid_axis(cab_drill.dir)
                            sign = grid_sign(cab_drill.dir)
                            @set! movement[axis] = cab_drill.t * sign
                            movement
                        end

    # Update shaking.
    shake_window = @f32(sin(cds.t * π) ^ 0.15) # Shake strength should fade in and out
    # Shake strength will be randomly distributed among the different shake types.
    # I'm not sure how to perfectly distribute continuous numbers,
    #    but distributing discrete elements is easy.
    shake_strengths = zero(Vec{NShakeModes, Float32})
    N_SEGMENTS = 10
    rng = ConstPRNG(cab_drill.rng_seed)
    for i in 1:N_SEGMENTS
        (bucket, rng) = rand(rng, 1:NShakeModes)
        @set! shake_strengths[bucket] += @f32(1 / N_SEGMENTS)
    end
    shake_strengths *= shake_window
    calculate_shake(entity.world.elapsed_seconds, shake_strengths, cab_drill.cosmetic_shake)

    return nothing
end