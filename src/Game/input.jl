# WASD: Strafe
# EQ: Climb

# Shift+WAD: Pass over gap to the straight/left/right

# JL: Turn
# IK: Look

# Shift+IJKL: Drill horizontally
# Shift+UO: Drill up/down


const INPUT_MODIFIERS = [
    tuple(Bplus.Input.ButtonInput(GLFW.KEY_LEFT_SHIFT),
          Bplus.Input.ButtonInput(GLFW.KEY_RIGHT_SHIFT)),
    tuple(Bplus.Input.ButtonInput(GLFW.KEY_LEFT_CONTROL),
          Bplus.Input.ButtonInput(GLFW.KEY_RIGHT_CONTROL))
]

"
A game input is a combination of modifier index and button.
Index of 0 means 'no modifier pressed'.
"
const GameInput = Tuple{Int, Vector{Bplus.Input.ButtonInput}}

const INPUT_MOVE_FORWARD = "P_MOVE_FORWARD" => (0, tuple(Bplus.Input.ButtonInput(GLFW.KEY_W)))
const INPUT_MOVE_BACK = "P_MOVE_BACK" => (0, tuple(Bplus.Input.ButtonInput(GLFW.KEY_S)))
const INPUT_MOVE_LEFT = "P_MOVE_LEFT" => (0, tuple(Bplus.Input.ButtonInput(GLFW.KEY_A)))
const INPUT_MOVE_RIGHT = "P_MOVE_RIGHT" => (0, tuple(Bplus.Input.ButtonInput(GLFW.KEY_D)))
const INPUT_CLIMB_UP = "P_CLIMB_UP" => (0, tuple(Bplus.Input.ButtonInput(GLFW.KEY_E)))
const INPUT_CLIMB_DOWN = "P_CLIMB_DOWN" => (0, tuple(Bplus.Input.ButtonInput(GLFW.KEY_Q)))

const INPUT_GAP_FORWARD = "P_GAP_FORWARD" => (1, tuple(Bplus.Input.ButtonInput(GLFW.KEY_W)))
const INPUT_GAP_LEFT = "P_GAP_LEFT" => (1, tuple(Bplus.Input.ButtonInput(GLFW.KEY_A)))
const INPUT_GAP_RIGHT = "P_GAP_RIGHT" => (1, tuple(Bplus.Input.ButtonInput(GLFW.KEY_D)))

const INPUT_TURN_RIGHT = "P_TURN_RIGHT" => (0, tuple(Bplus.Input.ButtonInput(GLFW.KEY_L)))
const INPUT_TURN_LEFT = "P_TURN_LEFT" => (0, tuple(Bplus.Input.ButtonInput(GLFW.KEY_J)))
const INPUT_LOOK_UP = "P_LOOK_UP" => (0, tuple(Bplus.Input.ButtonInput(GLFW.KEY_I)))
const INPUT_LOOK_DOWN = "P_LOOK_DOWN" => (0, tuple(Bplus.Input.ButtonInput(GLFW.KEY_K)))

const INPUT_DRILL_FORWARD = "P_DRILL_FORWARD" => (1, tuple(Bplus.Input.ButtonInput(GLFW.KEY_I)))
const INPUT_DRILL_BACKWARD = "P_DRILL_BACKWARD" => (1, tuple(Bplus.Input.ButtonInput(GLFW.KEY_K)))
const INPUT_DRILL_LEFT = "P_DRILL_LEFT" => (1, tuple(Bplus.Input.ButtonInput(GLFW.KEY_J)))
const INPUT_DRILL_RIGHT = "P_DRILL_RIGHT" => (1, tuple(Bplus.Input.ButtonInput(GLFW.KEY_L)))
const INPUT_DRILL_UP = "P_DRILL_UP" => (1, tuple(Bplus.Input.ButtonInput(GLFW.KEY_U)))
const INPUT_DRILL_DOWN = "P_DRILL_DOWN" => (1, tuple(Bplus.Input.ButtonInput(GLFW.KEY_O)))

const ALL_CAB_INPUTS = Dict([
    INPUT_MOVE_FORWARD,
    INPUT_MOVE_BACK,
    INPUT_MOVE_LEFT,
    INPUT_MOVE_RIGHT,
    INPUT_CLIMB_UP,
    INPUT_CLIMB_DOWN,

    INPUT_GAP_FORWARD,
    INPUT_GAP_LEFT,
    INPUT_GAP_RIGHT,

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
    for (name, (modifier, inputs)) in ALL_CAB_INPUTS
        create_button(name, inputs...)
    end
    for (i, inputs) in enumerate(INPUT_MODIFIERS)
        create_button("P_MODIFIER_$i", inputs...)
    end
end
function get_current_input_modifier_idx()::Int
    for i in 1:length(INPUT_MODIFIERS)
        if Bplus.Input.get_button("P_MODIFIER_$i")
            return i
        end
    end
    return 0
end

function update_mission_input_move(cab::Cab, grid::GridManager,
                                   move::CabMovementData, flip::Int,
                                   name::String
                                  )::Bool
    if Bplus.Input.get_button(name) && (ALL_CAB_INPUTS[name][1] == get_current_input_modifier_idx())
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
        (MOVE_RIGHT, 1, "P_MOVE_RIGHT")
    )
    args_climbing = (
        (MOVE_CLIMB_UP, 1, "P_CLIMB_UP"),
        (MOVE_CLIMB_DOWN, 1, "P_CLIMB_DOWN")
    )
    args_gapping = (
        (MOVE_GAP_FORWARD, 1, "P_GAP_FORWARD"),
        (MOVE_GAP_LEFT, 1, "P_GAP_LEFT"),
        (MOVE_GAP_RIGHT, 1, "P_GAP_RIGHT")
    )
    return any(update_mission_input_move.(Ref(cab), Ref(grid),
        Tuple(a[1] for a in args),
        Tuple(a[2] for a in args),
        Tuple(a[3] for a in args)
    )) || (cab.loadout.can_climb && any(update_mission_input_move.(Ref(cab), Ref(grid),
        Tuple(a[1] for a in args_climbing),
        Tuple(a[2] for a in args_climbing),
        Tuple(a[3] for a in args_climbing)
    ))) || (cab.loadout.can_cross_gaps && any(update_mission_input_move.(Ref(cab), Ref(grid),
        Tuple(a[1] for a in args_gapping),
        Tuple(a[2] for a in args_gapping),
        Tuple(a[3] for a in args_gapping)
    )))
end

function update_mission_input_turn(cab::Cab, grid::GridManager,
                                   degrees::Float32, name::String
                                  )::Bool
    if Bplus.Input.get_button(name) && (ALL_CAB_INPUTS[name][1] == get_current_input_modifier_idx())
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
    if Bplus.Input.get_button(name) && (ALL_CAB_INPUTS[name][1] == get_current_input_modifier_idx())
        facing_dir = grid_dir(cab.rot_component.rot)
        cab_forward = CabMovementDir(facing_dir, 1)
        if can_drill_from(cab.pos_component.get_voxel_position(), cab_forward, canonical_dir, grid)
            drill_dir = grid_dir(rotate_cab_movement(canonical_dir, cab_forward))
            player_start_drilling(cab, drill_dir)
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