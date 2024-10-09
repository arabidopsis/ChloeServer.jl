#!/bin/bash
# allow for julia connection
# using JuliaWebAPI
# import ChloeServer
# chloe = APIInvoker(ChloeServer.ZMQ_ENDPOINT)
# apicall(chloe, "ping")
exec julia -t8 --project=. -e 'using ChloeServer; main()' -- --level=info --workers=4 --broker=default
