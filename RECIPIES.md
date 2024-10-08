
## Server
To set up Chloë as a server that you can interact with, initiate the Chloë server: 

```sh
julia -t8 --project=. -e 'using ChloeServer; main()' -- \
    --level=info --workers=4 --broker=default
```

Then you can interact with this server using [JuliaWebAPI](https://github.com/JuliaWeb/JuliaWebAPI.jl). This utilises the JuliaWebAPI package to interact with a server running the Chloe package. It sends a request to annotate a fasta file, receives the annotation result along with the elapsed time, and then stops the server.


```julia
using JuliaWebAPI
import ChloeServer
i = APIInvoker(ChloeServer.ZMQ_ENDPOINT)
apicall(i, "ping") # ping the server to see if is listening.
# annotate a file
ret = apicall(i, "annotate", read("NC_011032.1.fa",String))
code, data = ret["code"], ret["data"]
@assert code == 200
# sff/gff file as a string and total elapsed
# time in ms to annotate
result, elapsed_ms = data["result"], data["elapsed"]

#stop the server....
apicall(i, "exit", )
```
## Running Remotely

The Chloë server can be run remotely through a ssh tunnel.

On the remote server:
`git clone ...` the chloe github repo and download the julia runtime (natch!).
*And* install all chloe package dependencies *globally* (see above).

Then -- on your puny laptop -- you can run something like:

```sh
ssh  you@bigserver -t -o ExitOnForwardFailure=yes -L 9476:127.0.0.1:9467 \
    'cd /path/to/chloe;
    JULIA_NUM_THREADS={BIGNUM} /path/to/bin/julia --project=. --startup-file=no --color=yes
    distributed.jl --broker=tcp://127.0.0.1:9467 -l info --workers=4'
```

The port `9467` is an entirely random (but hopefully unused both on
the remote server and locally) port number. The broker port *must* match
the ssh port specified by `-L`. `{BIGNUM}` is the enormous number
of CPUs your server has ;).

Since the remote server has no access to the local filesystem you need
to use `annotate` instead of `chloe` to annotate your your
fasta files e.g:

```julia
using JuliaWebAPI
i = APIInvoker("tcp://127.0.0.1:9467")
# read in the entire fasta file
fasta = read("testfa/NC_020019.1.fa", String)
ret = apicall(i, "annotate", fasta)
code, data = ret["code"], ret["data"]
@assert code === 200
sff = data["sff"] # sff file as a string
# terminate the server
apicall(i, "exit")
```
