cd(joinpath(@__DIR__, ".."))
insert!(LOAD_PATH, 1, ".")

using Drill8
exit(Drill8.julia_main())