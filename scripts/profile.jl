using Profile, ProfileView

cd(joinpath(@__DIR__, ".."))
insert!(LOAD_PATH, 1, ".")

# Configure the project for debugging.
using Bplus; @using_bplus
using Drill8
Drill8.d8_asserts_enabled() = true
BplusTools.ECS.bp_ecs_asserts_enabled() = true

# Profile the game.
@profview Drill8.julia_main()