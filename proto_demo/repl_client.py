#!/usr/bin/env python3
"""
Python REPL client that talks to a Perl Term::ReadLine::Repl-style server
via Protocol Buffers.

Each message on the pipe is framed as:
    [ 4-byte big-endian length ][ protobuf payload ]

The Perl server (repl_server.pl) reads ReplRequest messages, dispatches them
to the same cmd_schema you would use with Term::ReadLine::Repl, and returns
ReplResponse messages.  This demo shows how a proto layer lets any language
drive a Perl module without a JSON REST service in the middle.
"""

import os
import struct
import subprocess
import sys

# repl_pb2.py lives in the same directory as this script
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import repl_pb2


# ---------------------------------------------------------------------------
# Wire framing helpers
# ---------------------------------------------------------------------------

def write_request(pipe, command: str, args: list[str] = None) -> None:
    """Serialize a ReplRequest and write it length-prefixed to pipe."""
    req = repl_pb2.ReplRequest()
    req.command = command
    if args:
        req.args.extend(args)
    payload = req.SerializeToString()
    pipe.write(struct.pack(">I", len(payload)))
    pipe.write(payload)
    pipe.flush()


def read_response(pipe) -> repl_pb2.ReplResponse | None:
    """Read a length-prefixed ReplResponse from pipe; return None on EOF."""
    header = pipe.read(4)
    if len(header) < 4:
        return None
    length = struct.unpack(">I", header)[0]
    payload = pipe.read(length)
    if len(payload) < length:
        return None
    resp = repl_pb2.ReplResponse()
    resp.ParseFromString(payload)
    return resp


# ---------------------------------------------------------------------------
# Subprocess launcher
# ---------------------------------------------------------------------------

def start_server() -> subprocess.Popen:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_lib   = os.path.join(script_dir, "..", "lib")
    server     = os.path.join(script_dir, "repl_server.pl")

    # Use the local::lib path where Google::ProtocolBuffers was installed
    perl_lib = os.path.expanduser("~/.cpanm/work")  # fallback
    local_lib = "/tmp/perl5_fresh/lib/perl5"

    return subprocess.Popen(
        ["perl", f"-I{local_lib}", f"-I{repo_lib}", server],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=sys.stderr,   # surface any Perl errors directly in the terminal
    )


# ---------------------------------------------------------------------------
# Interactive REPL loop
# ---------------------------------------------------------------------------

def main() -> None:
    print("Starting Perl REPL server...", end=" ", flush=True)
    proc = start_server()
    print("connected.\n")
    print("Commands are dispatched via Protocol Buffers to a Perl process.")
    print("Type 'help' for commands, 'quit' to exit.\n")

    try:
        while True:
            try:
                line = input("repl> ").strip()
            except (EOFError, KeyboardInterrupt):
                print()
                line = "quit"

            if not line:
                continue

            parts   = line.split()
            command = parts[0]
            args    = parts[1:]

            write_request(proc.stdin, command, args)

            resp = read_response(proc.stdout)
            if resp is None:
                print("Server closed the connection unexpectedly.", file=sys.stderr)
                break

            if resp.output:
                print(resp.output, end="")

            if resp.should_exit:
                break

    finally:
        proc.stdin.close()
        proc.wait()


if __name__ == "__main__":
    main()
