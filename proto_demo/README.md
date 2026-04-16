# Term::ReadLine::Repl — Proto Demo

This demo shows a Python script driving a Perl `Term::ReadLine::Repl`-style
command dispatcher over a **Protocol Buffers** (protobuf) pipe.  It is a
proof-of-concept for wrapping legacy Perl modules in a proto layer so they can
be consumed cleanly from any other language.

---

## What are Protocol Buffers?

Protocol Buffers are Google's language-neutral, platform-neutral mechanism for
serializing structured data.  You define your data structures once in a `.proto`
file, run a code generator, and get native classes in every language you care
about — all producing and consuming the same compact binary wire format.

```
         repl.proto  (single source of truth)
              │
    ┌─────────┴──────────┐
    │                    │
repl_pb2.py          (inline in repl_server.pl)
(generated Python)   (parsed at runtime by Perl)
```

A proto message looks like a typed struct:

```protobuf
message ReplRequest {
    optional string command = 1;   // the command name
    repeated string args    = 2;   // zero or more arguments
}
```

Field numbers (the `= 1`, `= 2`) are what actually go on the wire — not the
names.  This is what makes the binary format so compact and what lets you rename
a field without breaking existing clients.

### Why protobuf instead of JSON?

| | JSON | Protobuf |
|---|---|---|
| Schema | Optional / informal | Required, enforced |
| Type safety | No | Yes — types checked at encode/decode |
| Wire size | Text, verbose | Binary, 3–10× smaller |
| Speed | Slow to parse | Fast |
| Code gen | None | Native classes in every language |
| Versioning | Convention only | Field numbers give safe evolution |
| Cross-language | Yes | Yes |

The schema is the biggest practical win.  With JSON you write docs and hope
consumers read them.  With protobuf the schema *is* the contract — if a field
doesn't exist in the `.proto`, it cannot appear in a message.

---

## The case for protobuf over a JSON REST micro-service

When the goal is to make a Perl module callable from Python (or Go, or Java,
or anything else), two common proposals come up:

**Option A — JSON REST micro-service**

Wrap the Perl module in a small HTTP server (Mojolicious, Dancer2, etc.), expose
endpoints like `POST /greet`, accept/return JSON.  Every caller needs an HTTP
client, you need to run and monitor an HTTP server, you add a network hop, you
define your API twice (once in code, once in docs), and JSON gives you no
compile-time guarantees on either side.

**Option B — Protobuf**

Define a `.proto` file.  Run `protoc` once.  You get generated classes in every
language that all speak the same binary protocol.  The Perl side can be a
long-running process, a subprocess, or eventually a gRPC service — the client
code barely changes.  No HTTP server, no network stack, no JSON parsing, no
separately maintained API docs.

For internal tooling sitting on the same machine or within a trusted network,
Option B is simpler to set up, faster, and self-documenting.  The `.proto` file
*is* the API documentation.

---

## How this demo is structured

```
proto_demo/
├── repl.proto          # Shared schema — the single source of truth
├── repl_pb2.py         # Generated Python bindings (do not edit)
├── repl_pb2.pyi        # Generated type stubs for IDE support
├── repl_server.pl      # Perl process: decodes requests, runs commands, encodes responses
└── repl_client.py      # Python process: interactive prompt over proto pipe
```

### The proto schema (`repl.proto`)

Two messages cover the entire interface:

```protobuf
message ReplRequest {
    optional string command = 1;   // e.g. "greet"
    repeated string args    = 2;   // e.g. ["Alice"]
}

message ReplResponse {
    optional bool   success            = 1;
    optional string output             = 2;   // human-readable result
    optional bool   should_exit        = 3;   // server signals clean shutdown
    repeated string available_commands = 4;   // populated by 'help'
}
```

### The Perl server (`repl_server.pl`)

The command schema is the same hashref structure you would pass to
`Term::ReadLine::Repl->new(cmd_schema => ...)`:

```perl
my %cmd_schema = (
    greet => {
        exec => sub { "Hello, " . ($_[0] // 'World') . "!\n" },
        help => 'Greet someone.  Usage: greet [name]',
    },
    add => { exec => sub { ... }, help => '...' },
    ...
);
```

The server loop reads length-prefixed `ReplRequest` messages from `STDIN`,
looks up the command in `%cmd_schema`, calls the `exec` coderef, and writes a
`ReplResponse` back to `STDOUT`.  The proto layer is roughly 40 lines on top
of business logic that never had to change.

### The Python client (`repl_client.py`)

The client forks `repl_server.pl` as a subprocess and opens pipes to its
`STDIN`/`STDOUT`.  From there it is a normal interactive prompt: read a line,
serialize it as a `ReplRequest`, write it down the pipe, read the `ReplResponse`
back, print the output.

```
Python client                       Perl server
─────────────────────────────────────────────────
input("repl> ")
split into command + args
ReplRequest.SerializeToString()
[4-byte length][binary payload] ──→ read(STDIN, ...)
                                    decode ReplRequest
                                    cmd_schema{cmd}{exec}->(@args)
                                    encode ReplResponse
                    STDOUT  ←── [4-byte length][binary payload]
ReplResponse.ParseFromString()
print(resp.output)
```

### Wire framing

Raw protobuf bytes have no built-in message boundary marker.  To send multiple
messages over a single persistent pipe, each message is prefixed with its length
as a 4-byte big-endian unsigned integer — the same framing used internally by
gRPC.

```
┌─────────────────────┬──────────────────────────────┐
│  length (4 bytes)   │  serialized proto (N bytes)  │
└─────────────────────┴──────────────────────────────┘
```

Both sides implement the same two helpers (`read_message` / `write_message` in
Perl, `read_response` / `write_request` in Python) — about 10 lines each.

---

## Running the demo

### Installation notes

#### Python

Install the protobuf runtime and the `grpcio-tools` code generator:

```bash
pip3 install grpcio-tools protobuf
```

**PEP 668 error on Ubuntu 24.04+** — if pip refuses with
`"error: externally-managed-environment"`, it means the OS is protecting its
system Python from pip-managed packages.  You have two options:

```bash
# Option A: force it (fine for a dev machine, not a server)
pip3 install --break-system-packages grpcio-tools protobuf

# Option B: use a virtualenv (cleaner, recommended for shared machines)
python3 -m venv .venv
source .venv/bin/activate
pip install grpcio-tools protobuf
```

We used `--break-system-packages` for this demo.

Regenerate the Python bindings any time `repl.proto` changes:

```bash
cd proto_demo
python3 -m grpc_tools.protoc -I. --python_out=. --pyi_out=. repl.proto
```

Note: the README in the `playing_with_protos` sibling demo warns against using
`protoc --python_out` directly and says to use `grpc_tools.protoc` instead.
The difference is that `grpc_tools.protoc` ships bundled with a version of
`protoc` that is tested against the Python `protobuf` package you installed,
avoiding version mismatches between the compiler and the runtime.

#### Perl

There are two Perl protobuf libraries and it matters which one you reach for:

| Module | Type | proto3 | Requires |
|---|---|---|---|
| `Google::ProtocolBuffers::Dynamic` | XS (native) | yes | `libprotobuf-dev` (apt), C++ toolchain |
| `Google::ProtocolBuffers` | Pure Perl | no (proto2 only) | nothing beyond Perl itself |

We tried `Google::ProtocolBuffers::Dynamic` first (it's what the
`playing_with_protos` demo uses and it supports proto3).  It failed to build
because it requires `libprotobuf-dev` and `libprotoc-dev` to be installed via
apt, which needs sudo:

```bash
# Only needed for Google::ProtocolBuffers::Dynamic — requires sudo
sudo apt install libprotobuf-dev libprotoc-dev protobuf-compiler
cpanm --notest Google::ProtocolBuffers::Dynamic
```

Without sudo we fell back to the pure-Perl `Google::ProtocolBuffers`, which has
no C dependencies and installs cleanly.  The trade-off is that it only speaks
**proto2 syntax**, which is why `repl.proto` is written with `syntax = "proto2"`
and `optional`/`repeated` labels rather than proto3's bare field declarations.
The binary wire format is identical either way, so the Python (proto3) and Perl
(proto2) sides interoperate without issues.

There was one more wrinkle: the copy of `Google::ProtocolBuffers` already in
`~/perl5` had been installed by a different Perl version, causing a `Storable`
ABI mismatch at runtime.  The fix was to install a fresh copy to a separate
local-lib path:

```bash
cpanm --notest --local-lib=/tmp/perl5_fresh Google::ProtocolBuffers
```

`/tmp` is ephemeral — this works for a demo but will disappear on reboot.  For
anything permanent, pick a stable path and update the `-I` flag in
`repl_client.py` accordingly:

```bash
# Example using ~/perl5_proto as a permanent location
cpanm --notest --local-lib=~/perl5_proto Google::ProtocolBuffers
# Then update repl_client.py:
#   local_lib = os.path.expanduser("~/perl5_proto/lib/perl5")
```

### Start the interactive client

```bash
cd proto_demo
python3 repl_client.py
```

```
Starting Perl REPL server... connected.

Commands are dispatched via Protocol Buffers to a Perl process.
Type 'help' for commands, 'quit' to exit.

repl> help
Available commands:
  add        Sum a list of numbers.  Usage: add <n> [n ...]
  greet      Greet someone.  Usage: greet [name]
  info       Show server info (PID, Perl version, time)
  reverse    Reverse a string.  Usage: reverse <text>
  upper      Uppercase text.  Usage: upper <text>
  help       Show this message
  quit       Exit the REPL

repl> greet Alice
Hello, Alice!

repl> add 10 20 30
Result: 60

repl> info
Server PID : 12345
Perl version: 5.038002
Time       : 2026-04-16 13:54:15

repl> quit
Goodbye!
```

---

## The bigger picture: wrapping legacy Perl modules

This demo uses a toy REPL, but the pattern scales directly to real internal
modules.  The migration path for any Perl module looks the same:

1. **Define a `.proto` file** for the module's public interface — one message
   per logical request/response pair.

2. **Write a thin Perl server** that parses proto messages, calls into the
   existing module, and returns proto responses.  The module itself does not
   change.

3. **Run `protoc`** once to generate bindings for whatever language the new
   consumer is written in.

4. **Write the consumer** using the generated classes.  It gets type-safe access
   to the Perl module's functionality without knowing Perl exists.

Because the `.proto` file is the contract, adding a new language consumer later
is just another `protoc` run — no new server code, no new docs, no JSON schema
to maintain separately.  When the Perl module's interface evolves, you update
the `.proto`, regenerate, and the compiler tells every consumer exactly what
changed.

---

## From raw protos to gRPC

This demo does everything manually: we fork a subprocess, frame messages with a
4-byte length prefix, and write our own dispatch loop.  That is deliberate — it
makes the proto layer visible and tangible.  But in a production setup you would
replace all of that plumbing with **gRPC**, and the payoff is significant.

### What gRPC adds on top of raw protos

gRPC is a complete RPC framework that uses protobuf as its wire format and
HTTP/2 as its transport.  The key addition is the `service` block in the
`.proto` file:

```protobuf
syntax = "proto3";

package repl;

service ReplService {
    rpc Execute (ReplRequest) returns (ReplResponse);
}

message ReplRequest {
    string command = 1;
    repeated string args = 2;
}

message ReplResponse {
    bool   success     = 1;
    string output      = 2;
    bool   should_exit = 3;
}
```

Running `protoc` with the gRPC plugin on that file generates two things for
every target language:

- A **client stub** — a class with a method `Execute()` that handles
  serialization, framing, the network call, and deserialization for you.
- A **server base class** — a class you subclass to implement `Execute()` on
  the server side.  gRPC handles everything else.

### What calling it looks like

This is where it clicks.  Instead of manually serializing a request, writing it
to a pipe, reading the response back, and deserializing it — you just call a
method on an object:

```python
import grpc
import repl_pb2
import repl_pb2_grpc   # generated service stub

# Connect to the Perl server running anywhere on the network
channel = grpc.insecure_channel('perl-server:50051')
stub    = repl_pb2_grpc.ReplServiceStub(channel)

# Call the remote Perl function exactly like a local function call
response = stub.Execute(repl_pb2.ReplRequest(command='greet', args=['Alice']))

print(response.output)   # Hello, Alice!
print(response.success)  # True
```

`response` is a real, typed Python object.  Its fields are defined in the
`.proto` and enforced by the generated code — not a dict you hope has the right
keys, not a JSON blob you need to parse.  You get IDE autocompletion, type
checking, and a runtime error if the server sends back something that doesn't
match the schema.

The same `.proto` file generates equivalent stubs in Go, Java, Ruby, Node.js,
C++, C#, Rust, and more.  A Go service, a Python script, and a Java application
can all call the same Perl server using generated client code that looks and
feels idiomatic in each language — none of them need to know Perl exists.

### What changes on the Perl side

Almost nothing.  The existing module code stays completely untouched.  You write
a thin gRPC server that:

1. Implements the generated server base class
2. In the `Execute` method, decodes the `ReplRequest`, calls into your existing
   Perl module, and returns a `ReplResponse`

The structure is identical to `repl_server.pl` — the only difference is that
gRPC handles the network socket, HTTP/2 framing, TLS, and connection management
instead of you doing it by hand.

> **Note on Perl gRPC support:** Native Perl gRPC libraries exist but are not
> as mature as the Python/Go/Java equivalents.  A practical approach is to keep
> the Perl business logic exactly as it is and put a thin Go or Python gRPC
> server in front of it — that server forks the Perl process and communicates
> with it using the exact proto-over-pipe pattern from this demo.  The external
> world sees a first-class gRPC service; internally it is still calling Perl.
> When/if Perl gRPC support matures, the external interface does not change at
> all.

### What you get for free with gRPC

Once you have a `service` definition, gRPC gives you things that are painful to
build yourself on top of raw HTTP or a hand-rolled REST API:

| Feature | Hand-rolled REST/JSON | gRPC |
|---|---|---|
| Client library | You write it (HTTP client + JSON parsing) | Generated — run `protoc` |
| Type safety | Hope the docs are right | Schema-enforced, compile-time |
| New language consumer | Rewrite the client | Run `protoc` again |
| Streaming | WebSockets, SSE, custom | First-class (`stream` keyword) |
| Deadlines / timeouts | Per-client convention | Built in to every call |
| TLS / auth | Configure per framework | Built in |
| Load balancing | External proxy | Built in |
| API docs | Write and maintain separately | The `.proto` file *is* the docs |

### The full migration path

```
Step 1 (this demo)
  Perl module ←→ proto messages ←→ subprocess pipe ←→ Python client
  One machine, manual framing, proves the concept.

Step 2
  Same proto messages, swap the pipe for a TCP socket.
  Now the Perl server and Python client can be on different machines.
  repl_client.py barely changes.

Step 3
  Add a service block to repl.proto.
  Run protoc with the gRPC plugin.
  Replace the hand-written framing code with the generated stub.
  You now have a production gRPC service.
  Any language can call your Perl module with generated client code.
```

The `.proto` message definitions you write in Step 1 carry forward unchanged
through every step.  The contract is set from day one.
