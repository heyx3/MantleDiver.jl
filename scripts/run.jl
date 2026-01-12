#=  Command-line arguments:
      * -d or --debug for a debug build
=#

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using Drill8

# Configure the project for debugging.
if ("-d" in ARGS) || ("--debug" in ARGS)
    using Bplus
    println(stderr, "Switching to debug mode...")
    @eval(@using_bplus)
    Drill8.d8_asserts_enabled() = true
    Bplus.ECS.bp_ecs_asserts_enabled() = true
    println(stderr, "Starting debug game...")
end

# Run and return the game's error code.
exit(Drill8.julia_main())