#!/usr/bin/env julia
if abspath(PROGRAM_FILE) == @__FILE__
    import ChloeServer
    ChloeServer.main(ARGS)
end
