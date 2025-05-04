# WASD: Strafe
# EQ: Climb

# Shift+WAD: Pass over gap to the straight/left/right

# JL: Turn
# IK: Look

# Shift+IJKL: Drill horizontally
# Shift+UO: Drill up/down


@bp_enum(PlayerHorizontalDir,
    forward, backward, left, right
)
@bp_enum(PlayerVerticalDir,
    up, down
)
@bp_enum(PlayerHorizontalAngleDir,
    left, right
)
@bp_enum(PlayerTDir,
    left, right, straight
)

struct InputMove
    dir::E_PlayerHorizontalDir
    name::String
    held_name::String
    InputMove(dir) = new(dir, "Mission: Move $dir", "Mission: Held: Move $dir")
end
struct InputClimb
    dir::E_PlayerVerticalDir
    name::String
    held_name::String
    InputClimb(dir) = new(dir, "Mission: Climb $dir", "Mission: Held: Climb $dir")
end
struct InputPassOverGap
    dir::E_PlayerTDir
    name::String
    held_name::String
    InputPassOverGap(dir) = new(dir, "Mission: Pass $dir over gap", "Mission: Held: Pass $dir over gap")
end
struct InputDrill
    dir::Union{E_PlayerHorizontalDir, E_PlayerVerticalDir}
    name::String
    held_name::String
    InputDrill(dir) = new(dir, "Mission: Drill $dir", "Mission: Held: Drill $dir")
end
struct InputTurn
    dir::E_PlayerHorizontalAngleDir
    name::String
    held_name::String
    InputTurn(dir) = new(dir, "Mission: Turn $dir", "Mission: Held: Turn $dir")
end
struct InputLook
    dir::E_PlayerVerticalDir
    name::String
    held_name::String
    InputLook(dir) = new(dir, "Mission: Look $dir", "Mission: Held: Look $dir")
end

InputAction = Union{InputMove, InputClimb, InputPassOverGap, InputDrill,
                    InputTurn, InputLook}
move_name(i::InputAction) = i.name
move_held_name(i::InputAction) = i.held_name


"Each entry is a set of modifiers that are all equivalent to each other (e.x. left + right shift)"
const INPUT_MODIFIERS = Pair{String, Vector{Bplus.Input.ButtonID}}[
    ("Mission: MODIFIER $i" => data) for (i, data) in enumerate([
        [ GLFW.KEY_LEFT_SHIFT, GLFW.KEY_RIGHT_SHIFT ],
        [ GLFW.KEY_LEFT_CONTROL, GLFW.KEY_RIGHT_CONTROL ],
        [ GLFW.KEY_LEFT_ALT, GLFW.KEY_RIGHT_ALT ]
    ])
]
const N_INPUT_MODIFIERS = length(INPUT_MODIFIERS)

"
A combination of input button and modifier (shift, ctrl, etc).

Modifiers are represented by their index in `INPUT_MODIFIERS`,
    with 0 representing 'no modifier'.
"
struct MissionInputButton
    button::Bplus.Input.ButtonInput
    modifier_idx::UInt

    MissionInputButton(button, idx = 0) = new(
        (button isa Bplus.Input.ButtonInput) ?
            button :
            Bplus.Input.ButtonInput(button, ButtonModes.just_pressed),
        UInt(idx)
    )
end


const INITIAL_INPUTS = Tuple{InputAction, MissionInputButton}[
    tuple(
        InputMove(PlayerHorizontalDir.forward),
        MissionInputButton(GLFW.KEY_W)
    ),
    tuple(
        InputMove(PlayerHorizontalDir.backward),
        MissionInputButton(GLFW.KEY_S)
    ),
    tuple(
        InputMove(PlayerHorizontalDir.left),
        MissionInputButton(GLFW.KEY_A)
    ),
    tuple(
        InputMove(PlayerHorizontalDir.right),
        MissionInputButton(GLFW.KEY_D)
    ),

    tuple(
        InputClimb(PlayerVerticalDir.up),
        MissionInputButton(GLFW.KEY_E)
    ),
    tuple(
        InputClimb(PlayerVerticalDir.down),
        MissionInputButton(GLFW.KEY_Q)
    ),

    tuple(
        InputPassOverGap(PlayerTDir.straight),
        MissionInputButton(GLFW.KEY_W, 1)
    ),
    tuple(
        InputPassOverGap(PlayerTDir.left),
        MissionInputButton(GLFW.KEY_A, 1)
    ),
    tuple(
        InputPassOverGap(PlayerTDir.right),
        MissionInputButton(GLFW.KEY_D, 1)
    ),

    tuple(
        InputTurn(PlayerHorizontalAngleDir.left),
        MissionInputButton(GLFW.KEY_J)
    ),
    tuple(
        InputTurn(PlayerHorizontalAngleDir.right),
        MissionInputButton(GLFW.KEY_L)
    ),

    tuple(
        InputLook(PlayerVerticalDir.up),
        MissionInputButton(GLFW.KEY_I)
    ),
    tuple(
        InputLook(PlayerVerticalDir.down),
        MissionInputButton(GLFW.KEY_K)
    ),

    tuple.(
        InputDrill.([
            PlayerHorizontalDir.forward,
            PlayerHorizontalDir.backward,
            PlayerHorizontalDir.left,
            PlayerHorizontalDir.right,
            PlayerVerticalDir.up,
            PlayerVerticalDir.down
        ]),
        MissionInputButton.([
            GLFW.KEY_I, GLFW.KEY_K,
            GLFW.KEY_J, GLFW.KEY_L,
            GLFW.KEY_U, GLFW.KEY_O
        ], Ref(1))
    )...
]
get_input_idx(a::InputAction)::Optional{Int} = findfirst(t -> t[1]==a, INITIAL_INPUTS)

function register_mission_inputs()
    for (action, input) in INITIAL_INPUTS
        create_button(
            move_name(action),
            input.button
        )
        create_button(
            move_held_name(action),
            Bplus.Input.ButtonInput(input.button.id, ButtonModes.down)
        )
    end
    for (name, buttons) in INPUT_MODIFIERS
        create_button(
            name,
            Bplus.Input.ButtonInput.(buttons, Ref(ButtonModes.down))...
        )
    end
end
function get_current_input_modifier_idx()::Int
    for (i, (name, _)) in enumerate(INPUT_MODIFIERS)
        if get_button(name)
            return i
        end
    end
    return 0
end


execute_input(mission, input)::Nothing = error("Unhandled: ", typeof(input))

function execute_input(mission::Mission, move::InputMove)
    if player_is_busy(mission.player.entity)
        return
    end

    movement_data::CabMovementData =
        if move.dir == PlayerHorizontalDir.forward
            MOVE_FORWARD
        elseif move.dir == PlayerHorizontalDir.backward
            MOVE_BACKWARD
        elseif move.dir == PlayerHorizontalDir.left
            MOVE_LEFT
        elseif move.dir == PlayerHorizontalDir.right
            MOVE_RIGHT
        else
            error("Unhandled: ", move.dir)
        end

    cab_grid_dir = grid_dir(mission.player.rot_component.rot)
    cab_move_dir = CabMovementDir(cab_grid_dir, 1)

    if can_do_move_from(mission.player.pos_component.get_voxel_position(),
                        cab_move_dir, movement_data, mission.grid)
        player_start_moving(mission.player.entity, movement_data, cab_move_dir)
    end

    return nothing
end
function execute_input(mission::Mission, climb::InputClimb)
    if player_is_busy(mission.player.entity)
        return
    end

    movement_data::CabMovementData =
        if climb.dir == PlayerVerticalDir.up
            MOVE_CLIMB_UP
        elseif climb.dir == PlayerVerticalDir.down
            MOVE_CLIMB_DOWN
        else
            error("Unhandled: ", climb.dir)
        end

    cab_grid_dir = grid_dir(mission.player.rot_component.rot)
    cab_move_dir = CabMovementDir(cab_grid_dir, 1)

    if can_do_move_from(mission.player.pos_component.get_voxel_position(),
                        cab_move_dir, movement_data, mission.grid)
        player_start_moving(mission.player.entity, movement_data, cab_move_dir)
    end

    return nothing
end
function execute_input(mission::Mission, pass::InputPassOverGap)
    if player_is_busy(mission.player.entity)
        return
    end

    movement_data::CabMovementData =
        if pass.dir == PlayerTDir.left
            MOVE_GAP_LEFT
        elseif pass.dir == PlayerTDir.right
            MOVE_GAP_RIGHT
        elseif pass.dir == PlayerTDir.straight
            MOVE_GAP_FORWARD
        else
            error("Unhandled: ", pass.dir)
        end

    cab_grid_dir = grid_dir(mission.player.rot_component.rot)
    cab_move_dir = CabMovementDir(cab_grid_dir, 1)

    if can_do_move_from(mission.player.pos_component.get_voxel_position(),
                        cab_move_dir, movement_data, mission.grid)
        player_start_moving(mission.player.entity, movement_data, cab_move_dir)
    end

    return nothing
end
function execute_input(mission::Mission, drill::InputDrill)
    if player_is_busy(mission.player.entity)
        return
    end

    canonical_dir::v3i =
        if drill.dir == PlayerHorizontalDir.forward
            v3i(1, 0, 0)
        elseif drill.dir == PlayerHorizontalDir.backward
            v3i(-1, 0, 0)
        elseif drill.dir == PlayerHorizontalDir.left
            v3i(0, -1, 0)
        elseif drill.dir == PlayerHorizontalDir.right
            v3i(0, 1, 0)
        elseif drill.dir == PlayerVerticalDir.up
            v3i(0, 0, 1)
        elseif drill.dir == PlayerVerticalDir.down
            v3i(0, 0, -1)
        else
            error("Unhandled: ", drill.dir)
        end

        facing_dir = grid_dir(mission.player.rot_component.rot)
        cab_forward = CabMovementDir(facing_dir, 1)

        if can_drill_from(mission.player.pos_component.get_voxel_position(),
                          cab_forward, canonical_dir, mission.grid)
            drill_dir = grid_dir(rotate_cab_movement(canonical_dir, cab_forward))
            player_start_drilling(mission.player, drill_dir)
        end
end
function execute_input(mission::Mission, turn::InputTurn)
    if player_is_busy(mission.player.entity)
        return
    end

    degrees =
        if turn.dir == PlayerHorizontalAngleDir.left
            TURN_INCREMENT_DEG
        elseif turn.dir == PlayerHorizontalAngleDir.right
            -TURN_INCREMENT_DEG
        else
            error("Unhandled: ", turn.dir)
        end
    player_start_turning(
        mission.player.entity,
        mission.player.rot_component.rot >> fquat(get_up_vector(), deg2rad(degrees))
    )
end
function execute_input(mission::Mission, look::InputLook)
    #TODO: Looking up/down
end

function update_mission_inputs(mission::Mission)::Nothing
    # First check that the game view has focus.
    gui_keyboard::Bool = unsafe_load(CImGui.GetIO().WantCaptureKeyboard)
    gui_mouse::Bool = unsafe_load(CImGui.GetIO().WantCaptureMouse)
    if gui_keyboard
        return nothing
    end

    # Precompute the modifier buttons (shift, ctrl, etc).
    modifiers = ntuple(i -> get_button(INPUT_MODIFIERS[i][1]),
                       Val(N_INPUT_MODIFIERS))

    # Try executing each action.
    for (action, input_data) in INITIAL_INPUTS
        modifier = if input_data.modifier_idx > 0
            modifiers[input_data.modifier_idx]
        else
            none(modifiers)
        end
        if modifier && get_button(move_name(action))
            execute_input(mission, action)
        end
    end

    return nothing
end