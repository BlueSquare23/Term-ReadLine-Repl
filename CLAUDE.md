# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Term::ReadLine::Repl** is a Perl module providing a batteries-included framework for building interactive CLI REPLs on top of Term::ReadLine. Users define commands as a data structure (schema-driven); the module handles the event loop, tab completion, history, help, and shell passthrough.

## Commands

```bash
# Install dependencies
cpanm --notest --installdeps .

# Build
perl Build.PL
./Build

# Run all tests
./Build test

# Run a single test file
perl -Ilib t/01_basic.t
```

CI tests against Perl 5.32, 5.36, and 5.38 on Ubuntu.

## Architecture

**Single module:** `lib/Term/ReadLine/Repl.pm`

**Constructor flow:** `new(%args)` → `validate_args()` → inject built-ins (`help`, `quit`, `exit`) → initialize Term::ReadLine + tab completion → optionally load history.

**Run loop** (`run()`):
1. Read input via Term::ReadLine
2. Exit on `quit`/`exit`
3. Skip empty input
4. Handle `help` (renders schema with args)
5. Handle `!cmd` shell passthrough (if `passthrough` enabled)
6. Call optional `get_opts` (Getopt::Long integration)
7. Call optional `custom_logic` (can short-circuit or swap the schema mid-loop)
8. Dispatch to the command's `exec` coderef

**Command schema** (the core API):
```perl
cmd_schema => {
    greet => {
        exec => sub { ... },           # required coderef
        args => [{ name => 'Alice' }], # optional array of hashrefs for tab completion
    },
}
```

**Tab completion** (`_tab_complete()`): completes command names on the first word, then values from `args` hashrefs on subsequent words. Shell passthrough commands (`!`) are filtered out of completion.

**Key constructor args:** `name` (required), `cmd_schema` (required), `prompt` (sprintf with `%s`), `passthrough` (bool), `hist_file` (path), `get_opts` (coderef), `custom_logic` (coderef receiving `@args`, returns `{action => 'next'|'last', schema => ...}`).

**Validation** is strict — `validate_args()` croaks with descriptive messages for any invalid arg type or missing required field.

## Tests

All tests are in `t/01_basic.t` using Test::More and Test::Exception. Tests cover: required-arg validation, schema structure validation, construction + built-in injection, prompt interpolation, and tab completion behavior.

See `example.pl` for a working REPL demonstrating typical usage.
