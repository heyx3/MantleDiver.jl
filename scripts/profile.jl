#NOTE: You must 'include()' this from the REPL! Otherwise, the profile data won't show up.
using InteractiveUtils
if !isinteractive()
    error("profile.jl can only be included from a REPL, not run automatically!")
end

# Load this project.
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using Drill8

# Set up the profiler.
using Profile, ProfileCanvas
@warn "RUNNING THE GAME ONCE FOR PRECOMPILATION..."
Drill8.julia_main()
@warn "RUNNING THE PROFILER ONCE FOR PRECOMPILATION..."
@profview map(identity, (i*i for i in 1:1000))

@profview Drill8.julia_main()