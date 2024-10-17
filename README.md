# ChloeServer

ZMQ based server for running Chloe 


## Chloë Server

Running the chloe server. In a terminal type:

```bash
julia -t8 --project=. distributed.jl --level=info --workers=4 --broker=default
# *OR*
julia -t8 --project=. -e 'using ChloeServer; main()' -- --level=info --workers=4 --broker=default
```

In another terminal start julia:

```julia
using JuliaWebAPI
import ChloeServer

i = APIInvoker(ChloeServer.ZMQ_ENDPOINT);
apicall(i, "ping") # ping the server to see if is listening.

# fasta and output should be relative to the server'
# working directory, or specify absolute path names! yes "chloe"
# should be "annotate" but...
fastafile = "testfa/NC_020019.1.fa"
ret = apicall(i, "chloe", fastafile)
code, data = ret["code"], ret["data"]
@assert code == 200
# actual filename written and total elapsed
# time in ms to annotate
sff_fname, elapsed_ms = data["filename"], data["elapsed"]
# to terminate the server cleanly (after finishing any work)
apicall(i, "exit")
```

The *actual* production configuration uses `distributed.jl`
(for threading issues) and runs
the server as a client of a DEALER/ROUTER server
(see `src/dist/broker.jl` and the `Makefile`). It *connects* to the
DEALER end on `tcp://127.0.0.1:9459`. The
[chloe website](https://chloe.plastid.org)
connects to `ipc:///tmp/chloe6-client` which
is the ROUTER end of broker. In this setup
you can run multiple chloe servers connecting
to the same DEALER.

**Update**: you can now run a broker with julia as `julia --project=. src/dist/broker.jl`
*or* specify `--broker=URL` to `distrbuted.jl`. No
python required. (best to use `--broker=default` to select
this projects default endpoint (`ChloeServer.ZMQ_ENDPOINT`))


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
@assert code == 200
sff = data["sff"] # sff file as a string
# terminate the server
apicall(i, "exit")
