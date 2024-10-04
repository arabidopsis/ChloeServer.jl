using JuliaWebAPI
import ChloeServer
# need the broker running...--broker=default
i = APIInvoker(ChloeServer.ZMQ_ENDPOINT)

println(apicall(i, "ping"))
ret = apicall(i, "annotate", read("junk/NC_011032.1.fa", String))

data = pop!(ret, "data")
result = pop!(data, "result")

println(data)
println(result)

# apicall(i, "exit")
