# Pass -d or --debug to enable asserts.

cd(joinpath(@__DIR__, ".."))
insert!(LOAD_PATH, 1, ".")
using Drill8

# Configure the project for debugging.
using Bplus
if ("-d" in ARGS) || ("--debug" in ARGS)
    println(stderr, "Running in debug mode...")
    @using_bplus
    Drill8.d8_asserts_enabled() = true
    BplusTools.ECS.bp_ecs_asserts_enabled() = true
end

# Run and return the game's error code.
exit(Drill8.julia_main())