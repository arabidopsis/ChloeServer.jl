
module Terminate
export terminate_me
import JuliaWebAPI: APIInvoker, run_http, process, create_responder
import Distributed: rmprocs, workers
function find_endpoint()
    endpoint = tmplt = joinpath(tempdir(), "chloe-terminate")
    n = 0
    while isfile(endpoint)
        n += 1
        endpoint = "$(tmplt)$(n)"
    end
    "ipc://$(endpoint)"
end

const JSON_RESP_HDRS = Dict{String,String}("Content-Type" => "application/json; charset=utf-8")

function terminate_me(port::Integer=9998)
    function terminate()
        @info "terminated..."
        @async begin
            sleep(2)
            procs = filter(w -> w != 1, workers())
            try
                rmprocs(procs...; waitfor=20)
            finally
                exit(0)
            end
        end
        return "OK\n"
    end
    # fn, resp_json, resp_headers, name
    # tasks = [(terminate, true, JSON_RESP_HDRS, "terminate")]
    tasks = [(terminate, false, Dict{String,String}(), "terminate")]
    endpoint = find_endpoint()
    # task listen, bind, id
    resp = create_responder(tasks, endpoint, true, nothing)
    process(resp; async=true)
    api = APIInvoker(endpoint)
    @info "terminate: listening on port $(port)"
    run_http(api, port)
end

end # module
