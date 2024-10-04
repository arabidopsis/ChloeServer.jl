#!/usr/bin/env python
import gzip
import os
import re
from concurrent.futures import ThreadPoolExecutor
from io import BytesIO, StringIO

import click
import zmq

# from chloe.config import ZMQ_ENDPOINT, ZMQ_WORKER

PORT = re.compile("^[0-9]+$")

JEXC = re.compile(r'ErrorException\("(.+)"\)')

context = zmq.Context.instance()

ZMQ_ENDPOINT = "ipc:///tmp/chloe5-client"
ZMQ_WORKER = "tcp://127.0.0.1:9458"

WORKER_PORT = int(ZMQ_WORKER.split(":")[-1])


class Socket:
    def __init__(self, address, timeout=None):
        self.socket, self.poller = self.setup_zmq(address)
        self.timeout = timeout

    def poll(self):
        if self.timeout:
            events = self.poller.poll(self.timeout)
            if not events:
                self.socket.close(linger=0)
                self.poller.unregister(self.socket)
                raise TimeoutError(f"no response after {self.timeout} milliseconds")

    def msg(self, **kwargs):
        try:
            self.socket.send_json(kwargs)
            self.poll()
            resp = self.socket.recv_json()
            return resp["code"], resp["data"]
        except TimeoutError as e:
            self.destroy()
            return 501, (e.args and e.args[0]) or str(e)

    # pylint: disable=no-self-use
    def setup_zmq(self, address):
        #  Socket to talk to server
        socket = context.socket(zmq.REQ)  # pylint: disable=no-member
        socket.connect(address)
        poller = zmq.Poller()
        poller.register(socket, zmq.POLLIN)
        return socket, poller

    def destroy(self):
        if self.socket is not None:
            s, p = self.socket, self.poller
            self.socket = self.poller = None
            p.unregister(s)
            s.close(linger=0)

    def __del__(self):
        if self:
            self.destroy()


def extract_exc(s):
    m = JEXC.search(s)
    if m:
        return m.group(1)
    return str(s)


# http://api.zeromq.org/2-1:zmq-setsockopt
def proxy(url_worker, url_client, hwm=1000):
    """Server routine"""
    try:
        # pylint: disable=no-member

        # Socket to talk to clients
        clients = context.socket(zmq.ROUTER)
        # number of *messages* in queue
        clients.setsockopt(zmq.RCVHWM, hwm)
        # clients.setsockopt(zmq.ZMQ_SWAP, swap)

        clients.bind(url_client)

        # Socket to talk to workers
        worker = context.socket(zmq.DEALER)
        worker.setsockopt(zmq.SNDHWM, hwm)
        # workers.setsockopt(zmq.ZMQ_SWAP, swap)
        worker.bind(url_worker)

        zmq.proxy(clients, worker)

        # We never get here but clean up anyhow
        clients.close(linger=0)
        workers.close(linger=0)
        context.term()
    except zmq.ZMQError as e:
        # probably Address already in use
        click.secho(f"broker: {e}", fg="red", bold=True, err=True)
        # we're in a thread.. need this to exit
        os._exit(1)  # pylint: disable=protected-access


HELP = f"""
Commands to directly connect to annotator

run the annotator as:

    {click.style('julia --project=. distributed.jl --broker=default', fg='green')}

"""


@click.group(epilog=HELP)
def cli():
    pass


# pylint: disable=redefined-outer-name
@cli.command()
@click.option(
    "-r",
    "--remote",
    type=int,
    help="remote port to connect to (the annotator) [default is same as local]",
)
@click.option(
    "-l",
    "--local",
    default=WORKER_PORT,
    help="local port to connect to (the broker)",
    show_default=True,
)
@click.option(
    "--broker",
    metavar="URL",
    help=f"run a broker endpoint too (use 'default' for {ZMQ_ENDPOINT})",
)
@click.option("-w", "--workers", default=8, help="number of processes to use")
@click.option("--sleep", default=0.0, help="sleep seconds before trying to connect")
@click.option("-t", "--threads", default=32, help="number of threads")
@click.option(
    "--level",
    default="info",
    help="log level for server",
    show_default=True,
    type=click.Choice(["info", "warn", "debug", "error"]),
)
@click.option(
    "-j",
    "--julia-dir",
    metavar="DIRECTORY",
    help="where julia located on server (will try to find it if not set)",
)
@click.option(
    "-a",
    "--annotator-repo",
    metavar="DIRECTORY",
    default="annotator",
    help="where chloe git repo is on server",
)
@click.argument("ssh_connection")
def remote_ssh(
    ssh_connection,
    remote,
    local,
    workers,
    level,
    sleep,
    broker,
    julia_dir,
    annotator_repo,
    threads,
):
    """start up a ssh tunnel to a server chloe-distributed using ssh connection."""
    from threading import Thread
    from time import sleep as Sleep
    from warnings import filterwarnings
    from fabric import Connection
    from cryptography.utils import CryptographyDeprecationWarning

    filterwarnings("ignore", category=CryptographyDeprecationWarning)

    if remote is None:
        remote = local

    if broker:
        address = f"tcp://127.0.0.1:{local}"
        if broker == "default":
            broker = ZMQ_ENDPOINT
        t = Thread(target=proxy, args=[address, broker], daemon=True)
        t.start()
        Sleep(sleep or 1.0)  # wait for it to start
    elif sleep:
        Sleep(sleep)
    c = Connection(ssh_connection)  # entry in ~/.ssh/config

    # bind on remote and connect on local
    # This means that the broker should be running first
    def run():
        with c.forward_remote(local_port=local, remote_port=remote):
            if julia_dir is not None:
                julia = os.path.join(julia_dir, "bin", "julia")
            else:
                res = c.run(
                    "PATH=$PATH:$HOME/bin julia -E Sys.BINDIR", warn=True, hide=True
                )
                if res.failed:
                    raise click.BadParameter(
                        "please specify the location of the julia directory",
                        param_hint="julia-dir",
                    )
                # strip "" quotes
                julia = os.path.join(res.stdout.strip()[1:-1], "julia")

            if c.run(f"test -f '{julia}'", warn=True, hide=True).failed:
                raise click.BadParameter(
                    "f{julia} is not an executable on: {ssh_connection}",
                    param_hint="julia-dir",
                )

            with c.cd(annotator_repo):

                args = f"""-l {level} --workers={workers} --address=tcp://127.0.0.1:{remote}"""
                cmd = (
                    f"JULIA_NUM_THREADS={threads} {julia} --color=yes --startup-file=no"
                    f" distributed.jl {args}"
                )
                # need a pty to send interrupt
                c.run(cmd, pty=True)
                click.secho("remote terminated", fg="green", bold=True)

    run()


def addresses(f):
    def callback(ctx, param, value):
        if PORT.match(value):
            return f"tcp://127.0.0.1:{value}"
        return value

    f = click.option(
        "-a",
        "--address",
        default=ZMQ_ENDPOINT,
        help="network address to connect to julia server",
        show_default=True,
        callback=callback,
    )(f)
    f = click.option(
        "-t",
        "--timeout",
        type=float,
        help="wait timeout in milliseconds [default: wait forever]",
    )(f)
    return f


@cli.command()
@addresses
@click.option(
    "--workers",
    default=0,
    help="send annotation requests in parallel using this many workers (default is cpu count)",
)
@click.option(
    "-o",
    "--output",
    required=True,
    help="output .sff filename or directory (relative to the server)",
)
@click.argument("fastas", nargs=-1)
def annotate(timeout, address, fastas, output, workers):
    """Annotate fasta files using a distributed chloe server."""
    from multiprocessing import cpu_count

    if workers == 0:
        workers = cpu_count()

    def dt(code, d):
        if code == 200:
            return ", ".join(f"{k}: {v}" for k, v in sorted(d.items()))
        return extract_exc(d)

    def do_one(fasta, socket=None):
        destroy = False
        if socket is None:
            destroy = True
            socket = Socket(address, timeout)

        code, data = socket.msg(cmd="chloe", args=[fasta, output])

        click.secho(
            f"{fasta}: [{dt(code,data)}]",
            fg="green" if code == 200 else "red",
            bold=True,
        )
        if destroy:
            socket.destroy()

    if workers > 1:
        with ThreadPoolExecutor(max_workers=workers) as pool:
            for fasta in fastas:
                pool.submit(do_one, fasta)
    else:
        socket = Socket(address, timeout)
        for fasta in fastas:
            do_one(fasta, socket)


def maybegz_open(fasta, mode="rt"):
    if fasta.endswith(".gz"):
        return gzip.open(fasta, mode)
    return open(fasta, mode)


def gzcompress(b):
    fasta = BytesIO()
    with gzip.GzipFile(fileobj=fasta, mode="wb") as fp:
        fp.write(b)
    return fasta.getvalue()


@cli.command()
@addresses
@click.option(
    "--workers",
    default=0,
    help="send annotation requests in parallel using this many workers (default is cpu count)",
)
@click.option("-o", "--output", help="output .sff filename or directory")
@click.option("--compress", is_flag=True, help="send fasta compressed")
@click.argument("fastas", nargs=-1)
def annotate2(timeout, address, compress, fastas, workers, output):
    """Annotate fasta files (send and receive file content)."""
    from multiprocessing import cpu_count

    socket = Socket(address, timeout)

    if workers == 0:
        workers = cpu_count()

    def get_fasta(fasta):
        if compress:
            with open(fasta, "rb") as fp:
                b = fp.read()
            if not fasta.endswith(".gz") or b.startswith(b">"):
                b = gzcompress(b)
            fasta_str = b.decode("latin1")
            if not fasta_str.startswith("\x1f\x8b"):
                raise click.BadParameter(
                    f"not a gzipped file: {fasta}", param_hint="fastas"
                )
        else:
            with maybegz_open(fasta) as fp:
                fasta_str = fp.read().lstrip()
        return fasta_str

    def do_one(fasta, socket=None):
        destroy = False
        if socket is None:
            destroy = True
            socket = Socket(address, timeout)
        fasta_str = get_fasta(fasta)
        code, data = socket.msg(cmd="annotate", args=[fasta_str])
        if destroy:
            socket.destroy()

        if code != 200:
            click.secho(extract_exc(data), fg="red", bold=True, err=True)
            return

        ncid, sff = data["ncid"], data["sff"]
        click.secho(ncid, fg="green", err=True)
        if not output:
            with StringIO(sff) as fp:
                for line in fp:
                    print(line, end="")
        else:
            if os.path.isdir(output):
                tgt = os.path.join(output, f"{ncid}.sff")
            else:
                tgt = output
            with open(tgt, "wt") as fp:
                fp.write(sff)

    if workers > 1:
        with ThreadPoolExecutor(max_workers=workers) as pool:
            for fasta in fastas:
                pool.submit(do_one, fasta)
    else:
        socket = Socket(address, timeout)
        for fasta in fastas:
            do_one(fasta, socket)


@cli.command()
@addresses
def terminate(timeout, address):
    """Terminate a single worker."""
    socket = Socket(address, timeout)

    code, msg = socket.msg(cmd=":terminate")
    click.secho(
        "OK" if code == 200 else msg or f"No Server at {address}",
        fg="green" if code == 200 else "red",
        bold=True,
    )


def display(code, data):
    if code != 200:
        resp = extract_exc(data)
    else:
        resp = str(data)
    click.secho(resp, fg="green" if code == 200 else "red", bold=True)


@cli.command(name="exit")
@addresses
def exitit(timeout, address):
    """Shutdown the server."""

    def h(s):
        return click.style(s, fg="yellow", bold=True)

    click.echo(
        f"""
{h("Warning!")}: sending and "extra" `exit` via the broker when
the annotator is down may kill it as soon as it starts up again.
(Since the kill request will remain "lurking" in the broker queue.)

{h("Don't run this twice in a row!")}.
"""
    )
    socket = Socket(address, timeout)
    code, data = socket.msg(cmd="exit", args=[address])
    display(code, data)


@cli.command()
@addresses
def ping(timeout, address):
    """Ping the server."""
    socket = Socket(address, timeout)
    code, data = socket.msg(cmd="ping")
    display(code, data)


@cli.command()
@addresses
def workers(timeout, address):
    """Number of service workers"""
    socket = Socket(address, timeout)
    code, data = socket.msg(cmd="nconn")
    display(code, data)


@cli.command()
@addresses
@click.option(
    "-w",
    "--workers",
    type=int,
    required=True,
    help="number of workers to add or remove",
)
def add_workers(timeout, address, workers):
    """add or remove service workers"""
    socket = Socket(address, timeout)
    code, data = socket.msg(cmd="add_workers", args=[workers, address])
    display(code, data)


if __name__ == "__main__":
    cli()
