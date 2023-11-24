##   Abstract component   ##

# "Some kind of animated motion. Only one maneuver can run at a time."
@component Maneuver {abstract} {entitySingleton} {require: ContinuousPosition} begin
    pos_component::ContinuousPosition
    shake_component::CosmeticOffset

    duration::Float32
    progress_normalized::Float32

    function CONSTRUCT(duration_seconds)
        this.progress_normalized = 0
        this.duration = convert(Float32, duration_seconds)
        this.pos_component = get_component(entity, ContinuousPosition)
        this.shake_component = add_component(entity, CosmeticOffset)
    end
    function DESTRUCT(is_entity_dying::Bool)
        if !is_entity_dying
            remove_component(entity, this.shake_component)
        end
    end

    @promise finish_maneuver()
    @configurable shake_strengths()::Vec{NShakeModes, Float32} = zero(Vec{NShakeModes, Float32})

    function TICK()
        this.progress_normalized += world.delta_seconds / this.duration

        # Calculate shaking.
        shake_strengths = this.shake_strengths()
        shake_states = Vec{NShakeModes, CabShakeState}(
            i -> CAB_SHAKE_MODES[i](world.elapsed_seconds)
        )
        # Apply shaking to the entity.
        this.shake_component.pos = sum(
            state.pos * strength
              for (state, strength) in zip(shake_states, shake_strengths)
        )
        this.shake_component.rot = let rot = fquat()
            for (state, strength) in zip(shake_states, shake_strengths)
                rot >>= fquat(get_up_vector(), state.yaw * strength)
                rot >>= fquat(get_horz_vector(2), state.pitch * strength)
                rot >>= fquat(get_horz_vector(1), state.roll * strength)
            end
            rot
        end
    end
    function FINISH_TICK()
        if this.progress_normalized >= 1
            this.finish_maneuver()
            remove_component(entity, this)
        end
    end
end


##   Turning   ##

const TURN_SPEED_DEG_PER_SECOND = 180

# "Manages a cab's turning motion"
@component CabTurn <: Maneuver {require: WorldOrientation} begin
    rot_component::WorldOrientation
    target::fquat

    CONSTRUCT(target) = begin
        this.rot_component = get_component(entity, WorldOrientation)
        this.target = convert(fquat, target)

        #TODO: B+ function to calculate the angle delta between two orientations
        total_angle = acos(vdot(q_apply(this.rot_component.rot,
                                        v3f(1, 0, 0)),
                                q_apply(this.target,
                                        v3f(1, 0, 0))))
        SUPER(rad2deg(total_angle) / TURN_SPEED_DEG_PER_SECOND)
    end

    TICK() = begin
        # Calculate the full turn needed to make it to the target.
        forward::v3f = q_apply(this.rot_component.rot, get_horz_vector(1))
        desired_forward::v3f = q_apply(this.target, get_horz_vector(1))
        full_turn = fquat(forward, desired_forward)
        (turn_axis, turn_radians) = q_axisangle(full_turn)

        # Constrain the turn based on the size of the time-step.
        delta_seconds::Float32 = entity.world.delta_seconds
        frame_max_rad = deg2rad(delta_seconds * TURN_SPEED_DEG_PER_SECOND)

        # Apply the turn movement.
        this.rot_component.rot >>= fquat(turn_axis, copysign(frame_max_rad, turn_radians))
    end
    finish_maneuver() = (this.rot_component.rot = this.target)
end


##   Movement   ##

# "Plays out a Cab movement animation"
@component CabMovement <: Maneuver begin
    original_pos::v3f
    key_idx::Int
    computed_shake_strengths::Vec{NShakeModes, Float32}
    src::CabMovementData
    heading::CabMovementDir

    function CONSTRUCT(src::CabMovementData, heading::CabMovementDir)
        SUPER(src.time_seconds)
        this.original_pos = this.pos_component.pos
        this.key_idx = 1
        this.src = src
        this.heading = heading
        this.computed_shake_strengths = zero(Vec{NShakeModes, Float32})
    end

    function TICK()
        cab_move_forward(this, entity, world, world.delta_seconds)
    end
    finish_maneuver() = begin
        this.pos_component.pos = +(
            this.original_pos,
            rotate_cab_movement(this.src.keyframes[end].delta_pos,
                                this.heading)
        )
    end

    shake_strengths() = this.computed_shake_strengths
end

function cab_move_forward(this::CabMovement, entity::Entity, world::World,
                          delta_seconds::Float32)
    # Get the previous animation key, or a stand-in if we're at the first key.
    local prev_key::CabMovementKeyframe
    if this.key_idx == 1
        prev_key = CabMovementKeyframe(zero(v3f), zero(Float32),
                                       zero(Vec{NShakeModes, Float32}))
    else
        prev_key = this.src.keyframes[this.key_idx - 1]
    end

    next_key = this.src.keyframes[this.key_idx]

    # Rotate the keyframes to face our actual heading.
    @set! prev_key.delta_pos = rotate_cab_movement(prev_key.delta_pos, this.heading)
    @set! next_key.delta_pos = rotate_cab_movement(next_key.delta_pos, this.heading)

    # If this tick would go past the current keyframe, cut it off at that keyframe
    #    and make a recursive call to process the next one.
    time_to_next_keyframe = (next_key.t - this.progress_normalized) * this.duration
    passes_keyframe::Bool = time_to_next_keyframe <= delta_seconds
    capped_delta_seconds = passes_keyframe ? time_to_next_keyframe : delta_seconds

    # Update the position, or move on to the next keyframe if time is left.
    if passes_keyframe
        if this.key_idx < length(this.src.keyframes)
            this.key_idx += 1
            cab_move_forward(this, entity, world, delta_seconds - time_to_next_keyframe)
        else
            # Already handled by this.finish_maneuver()
        end
    else
        frame_t::Float32 = inv_lerp(prev_key.t, next_key.t, this.progress_normalized)
        this.pos_component.pos = this.original_pos +
                                 lerp(prev_key.delta_pos, next_key.delta_pos, frame_t)
        this.computed_shake_strengths = lerp(
            prev_key.shake_strengths,
            next_key.shake_strengths,
            frame_t
        )
    end
end


##   Drilling   ##

@component CabDrill <: Maneuver begin
    original_pos::v3f

    dir::GridDirection
    rng_seed::Float32

    function CONSTRUCT(dir::GridDirection, rng_seed::Float32)
        SUPER(DRILL_DURATION_SECONDS)
        this.original_pos = this.pos_component.pos
        this.dir = dir
        this.rng_seed = rng_seed
    end

    function TICK()
        movement = zero(v3f)
        @set! movement[grid_axis(this.dir)] = this.progress_normalized *
                                              grid_sign(this.dir)

        this.pos_component.pos = this.original_pos + movement
    end
    function finish_maneuver()
        delta = zero(v3f)
        @set! delta[grid_axis(this.dir)] = grid_sign(this.dir)
        this.pos_component.pos = this.original_pos + delta

        grid = get_component(world, GridManager)[1]
        voxel = this.pos_component.get_voxel_position()
        rock = grid.entities[voxel]
        if isnothing(rock)
            @warn "Drilled into an empty spot! Something else destroyed it first?"
        else
            remove_entity(world, rock)
        end
    end

    function shake_strengths()
        # Shake strength should fade in and out.
        shake_window = @f32(saturate(sin(this.progress_normalized * π)) ^ 0.15)

        # Shake strength will be randomly distributed among the different shake types.
        # I'm not sure how to perfectly distribute continuous numbers,
        #    but distributing discrete elements is easy.
        shake_strengths = zero(Vec{NShakeModes, Float32})
        N_SEGMENTS = 10
        rng = ConstPRNG(this.rng_seed)
        for i in 1:N_SEGMENTS
            (bucket, rng) = rand(rng, 1:NShakeModes)
            @set! shake_strengths[bucket] += @f32(1 / N_SEGMENTS)
        end

        return shake_strengths * shake_window
    end
end