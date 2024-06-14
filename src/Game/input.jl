const INITIAL_INPUT_TURN_RIGHT = tuple(Bplus.Input.ButtonInput(GLFW.KEY_A))
const INITIAL_INPUT_TURN_LEFT = tuple(Bplus.Input.ButtonInput(GLFW.KEY_D))

const INITIAL_INPUT_FORWARD = tuple(Bplus.Input.ButtonInput(GLFW.KEY_ENTER))
const INITIAL_INPUT_CLIMB_UP = tuple(Bplus.Input.ButtonInput(GLFW.KEY_UP))
const INITIAL_INPUT_CLIMB_DOWN = tuple(Bplus.Input.ButtonInput(GLFW.KEY_DOWN))

const INITIAL_INPUT_DRILL_FORWARD = tuple(Bplus.Input.ButtonInput(GLFW.KEY_I))
const INITIAL_INPUT_DRILL_DOWN = tuple(Bplus.Input.ButtonInput(GLFW.KEY_K))
const INITIAL_INPUT_DRILL_LEFT = tuple(Bplus.Input.ButtonInput(GLFW.KEY_J))
const INITIAL_INPUT_DRILL_RIGHT = tuple(Bplus.Input.ButtonInput(GLFW.KEY_L))

function register_mission_inputs()
    create_button("P_FORWARD", INITIAL_INPUT_FORWARD...)
    create_button("P_CLIMB_UP", INITIAL_INPUT_CLIMB_UP...)
    create_button("P_CLIMB_DOWN", INITIAL_INPUT_CLIMB_DOWN...)

    create_button("P_TURN_RIGHT", INITIAL_INPUT_TURN_RIGHT...)
    create_button("P_TURN_LEFT", INITIAL_INPUT_TURN_LEFT...)

    create_button("P_DRILL_FORWARD", INITIAL_INPUT_DRILL_FORWARD...)
    create_button("P_DRILL_DOWN", INITIAL_INPUT_DRILL_DOWN...)
    create_button("P_DRILL_LEFT", INITIAL_INPUT_DRILL_LEFT...)
    create_button("P_DRILL_RIGHT", INITIAL_INPUT_DRILL_RIGHT...)
end

const TURN_INCREMENT_DEG = @f32(30)

function update_mission_inputs(mission::Mission)
    gui_keyboard::Bool = unsafe_load(CImGui.GetIO().WantCaptureKeyboard)
    gui_mouse::Bool = unsafe_load(CImGui.GetIO().WantCaptureMouse)

    if gui_keyboard
        # Skip input checking; Dear ImGUI is capturing all input.
    elseif !player_is_busy(mission.player)
        player_grid_direction = grid_dir(mission.player_rot.rot)
        player_voxel = mission.player_pos.get_voxel_position()

        function try_move(m, flip=1)
            move_dir = CabMovementDir(player_grid_direction, flip)
            if can_do_move_from(player_voxel, move_dir, m, mission.grid)
                player_start_moving(mission.player, m, move_dir)
            end
        end
        function try_turn(rot_degrees::Float32)
            turn = fquat(get_up_vector(), deg2rad(rot_degrees))
            new_orientation = mission.player_rot.rot >> turn
            player_start_turning(mission.player, new_orientation)
        end
        function can_drill(canonical_dir::Vec3, flip=1)
            drill_dir = CabMovementDir(player_grid_direction, flip)
            return can_drill_from(player_voxel, drill_dir, canonical_dir, mission.grid)
        end

        if Bplus.Input.get_button("P_FORWARD")
            try_move(LEGAL_MOVES[1])
        elseif get_button("P_CLIMB_UP")
            try_move(LEGAL_MOVES[2])
        elseif get_button("P_CLIMB_DOWN")
            try_move(LEGAL_MOVES[3])
        #TODO: Swing-around-corner-with-no-floor movements
        elseif get_button("P_TURN_RIGHT")
            try_turn(TURN_INCREMENT_DEG)
        elseif get_button("P_TURN_LEFT")
            try_turn(-TURN_INCREMENT_DEG)
        elseif get_button("P_DRILL_FORWARD")
            if can_drill(v3f(1, 0, 0))
                player_start_drilling(mission.player, grid_dir(mission.player_rot.rot))
            end
        elseif get_button("P_DRILL_DOWN")
            if can_drill(v3f(0, 0, -1))
                player_start_drilling(mission.player, grid_dir(-get_up_vector()))
            end
        elseif get_button("P_DRILL_LEFT")
            if can_drill(v3i(0, 1, 0), -1)
                drill_dir = CabMovementDir(player_grid_direction, -1)
                player_start_drilling(mission.player,
                                      grid_dir(rotate_cab_movement(v3i(0, 1, 0), drill_dir)))
            end
        elseif get_button("P_DRILL_RIGHT")
            if can_drill(v3i(0, 1, 0), 1)
                drill_dir = CabMovementDir(player_grid_direction, 1)
                player_start_drilling(mission.player,
                                      grid_dir(rotate_cab_movement(v3i(0, 1, 0), drill_dir)))
            end
        end
    end
end