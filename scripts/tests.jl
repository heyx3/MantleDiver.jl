cd(joinpath(@__DIR__, ".."))
insert!(LOAD_PATH, 1, ".")
insert!(LOAD_PATH, 1, "test")

include(joinpath(@__DIR__, "..", "test", "runtests.jl"))