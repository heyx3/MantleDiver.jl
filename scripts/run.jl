cd(joinpath(@__DIR__, ".."))
insert!(LOAD_PATH, 1, ".")

# Configure the project for debugging.
using Drill8
Drill8.ECS.ecs_asserts_enabled() = true

# Run and return the game's error code.
exit(Drill8.julia_main())