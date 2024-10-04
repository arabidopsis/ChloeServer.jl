using JuliaWebAPI
import Chloe
i = APIInvoker(Chloe.ZMQ_ENDPOINT)

println(apicall(i, "ping"))
println(apicall(i, "annotate", read("junk/NC_011032.1.fa",String)))

apicall(i, "exit")
