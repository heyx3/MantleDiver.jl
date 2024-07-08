const INPUT_MOVE_FORWARD = "P_MOVE_FORWARD" => tuple(Bplus.Input.ButtonInput(GLFW.KEY_W))
const INPUT_MOVE_BACK = "P_MOVE_BACK" => tuple(Bplus.Input.ButtonInput(GLFW.KEY_S))
const INPUT_MOVE_LEFT = "P_MOVE_LEFT" => tuple(Bplus.Input.ButtonInput(GLFW.KEY_A))
const INPUT_MOVE_RIGHT = "P_MOVE_RIGHT" => tuple(Bplus.Input.ButtonInput(GLFW.KEY_D))
const INPUT_CLIMB_UP = "P_CLIMB_UP" => tuple(Bplus.Input.ButtonInput(GLFW.KEY_E))
const INPUT_CLIMB_DOWN = "P_CLIMB_DOWN" => tuple(Bplus.Input.ButtonInput(GLFW.KEY_Q))

const INPUT_TURN_RIGHT = "P_TURN_RIGHT" => tuple(Bplus.Input.ButtonInput(GLFW.KEY_RIGHT))
const INPUT_TURN_LEFT = "P_TURN_LEFT" => tuple(Bplus.Input.ButtonInput(GLFW.KEY_LEFT))
const INPUT_LOOK_UP = "P_LOOK_UP" => tuple(Bplus.Input.ButtonInput(GLFW.KEY_UP))
const INPUT_LOOK_DOWN = "P_LOOK_DOWN" => tuple(Bplus.Input.ButtonInput(GLFW.KEY_DOWN))

const INPUT_DRILL_FORWARD = "P_DRILL_FORWARD" => tuple(Bplus.Input.ButtonInput(GLFW.KEY_I))
const INPUT_DRILL_BACKWARD = "P_DRILL_BACKWARD" => tuple(Bplus.Input.ButtonInput(GLFW.KEY_K))
const INPUT_DRILL_LEFT = "P_DRILL_LEFT" => tuple(Bplus.Input.ButtonInput(GLFW.KEY_J))
const INPUT_DRILL_RIGHT = "P_DRILL_RIGHT" => tuple(Bplus.Input.ButtonInput(GLFW.KEY_L))
const INPUT_DRILL_UP = "P_DRILL_UP" => tuple(Bplus.Input.ButtonInput(GLFW.KEY_U))
const INPUT_DRILL_DOWN = "P_DRILL_DOWN" => tuple(Bplus.Input.ButtonInput(GLFW.KEY_O))

const ALL_CAB_INPUTS = Dict([
    INPUT_MOVE_FORWARD,
    INPUT_MOVE_BACK,
    INPUT_MOVE_LEFT,
    INPUT_MOVE_RIGHT,
    INPUT_CLIMB_UP,
    INPUT_CLIMB_DOWN,

    INPUT_TURN_RIGHT,
    INPUT_TURN_LEFT,
    INPUT_LOOK_UP,
    INPUT_LOOK_DOWN,

    INPUT_DRILL_FORWARD,
    INPUT_DRILL_BACKWARD,
    INPUT_DRILL_LEFT,
    INPUT_DRILL_RIGHT,
    INPUT_DRILL_UP,
    INPUT_DRILL_DOWN
])

function register_mission_inputs()
    for (name, inputs) in ALL_CAB_INPUTS
        create_button(name, inputs...)
    end
end


const TURN_INCREMENT_DEG = @f32(30)

# Short-hands for move definitions
const CMKf = CabMovementKeyframe
const SV = Vec{N_SHAKE_MODES, Float32}

const MOVE_FORWARD = CabMovementData(
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
)
const MOVE_BACKWARD = CabMovementData(
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
)
const MOVE_LEFT = CabMovementData(
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
)
const MOVE_RIGHT = CabMovementData(
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
)
const MOVE_CLIMB_UP = CabMovementData(
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
)
const MOVE_CLIMB_DOWN = CabMovementData(
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
)
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


function update_mission_input_move(cab::Cab, grid::GridManager,
                                   move::CabMovementData, flip::Int,
                                   name::String
                                  )::Bool
    if Bplus.Input.get_button(name)
        cab_grid_dir = grid_dir(cab.rot_component.rot)
        cab_move_dir = CabMovementDir(cab_grid_dir, flip)
        if can_do_move_from(cab.pos_component.get_voxel_position(), cab_move_dir, move, grid)
            player_start_moving(cab.entity, move, cab_move_dir)
            return true
        end
    end
    return false
end
function update_mission_inputs_move(cab::Cab, grid::GridManager)
    args = (
        (MOVE_FORWARD, 1, "P_MOVE_FORWARD"),
        (MOVE_BACKWARD, 1, "P_MOVE_BACK"),
        (MOVE_LEFT, 1, "P_MOVE_LEFT"),
        (MOVE_RIGHT, 1, "P_MOVE_RIGHT"),
        (MOVE_CLIMB_UP, 1, "P_CLIMB_UP"),
        (MOVE_CLIMB_DOWN, 1, "P_CLIMB_DOWN")
    )
    return any(update_mission_input_move.(Ref(cab), Ref(grid),
        Tuple(a[1] for a in args),
        Tuple(a[2] for a in args),
        Tuple(a[3] for a in args)
    ))
end

function update_mission_input_turn(cab::Cab, grid::GridManager,
                                   degrees::Float32, name::String
                                  )::Bool
    if Bplus.Input.get_button(name)
        player_start_turning(
            cab.entity,
            cab.rot_component.rot >> fquat(get_up_vector(), deg2rad(degrees))
        )
        return true
    end
    return false
end
function update_mission_inputs_turn(cab, grid::GridManager)
    args = (
        (TURN_INCREMENT_DEG, "P_TURN_LEFT"),
        (-TURN_INCREMENT_DEG, "P_TURN_RIGHT")
    )
    return any(update_mission_input_turn.(Ref(cab), Ref(grid),
        Tuple(a[1] for a in args),
        Tuple(a[2] for a in args)
    ))
end

function update_mission_input_drill(cab::Cab, grid::GridManager,
                                    canonical_dir::Vec3, name::String
                                   )::Bool
    if Bplus.Input.get_button(name)
        facing_dir = grid_dir(cab.rot_component.rot)
        cab_forward = CabMovementDir(facing_dir, 1)
        if can_drill_from(cab.pos_component.get_voxel_position(), cab_forward, canonical_dir, grid)
            drill_dir = grid_dir(rotate_cab_movement(canonical_dir, cab_forward))
            player_start_drilling(cab.entity, drill_dir)
            return true
        end
    end
    return false
end
function update_mission_inputs_drill(cab::Cab, grid::GridManager)::Bool
    args = (
        (v3i(1, 0, 0), "P_DRILL_FORWARD"),
        (v3i(-1, 0, 0), "P_DRILL_BACKWARD"),
        (v3i(0, 1, 0), "P_DRILL_RIGHT"),
        (v3i(0, -1, 0), "P_DRILL_LEFT"),
        (v3i(0, 0, 1), "P_DRILL_UP"),
        (v3i(0, 0, -1), "P_DRILL_DOWN")
    )
    return any(update_mission_input_drill.(Ref(cab), Ref(grid),
        Tuple(a[1] for a in args),
        Tuple(a[2] for a in args)
    ))
end

function update_mission_inputs(mission::Mission)
    gui_keyboard::Bool = unsafe_load(CImGui.GetIO().WantCaptureKeyboard)
    gui_mouse::Bool = unsafe_load(CImGui.GetIO().WantCaptureMouse)

    if !gui_keyboard && !player_is_busy(mission.player.entity)
        update_mission_inputs_drill(mission.player, mission.grid) ||
        update_mission_inputs_move(mission.player, mission.grid) ||
        update_mission_inputs_turn(mission.player, mission.grid)
    end
end