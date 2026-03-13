# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.1] - 2026-03-13

### Added

- Initial release of `Term::ReadLine::Repl`.
- Basic REPL loop with prompt, welcome message, and `help`/`quit` built-in commands.
- Tab auto-completion for command names and their defined arguments.
- Argument validation in `validate_args()` with descriptive croak messages for
  missing or malformed constructor args.
- `get_opts` support for integrating a `Getopt::Long` parsing function into the loop.
- `custom_logic` hook allowing callers to inject mid-loop logic, control flow
  (`next`/`last`), and dynamic `cmd_schema` changes.
- `passthrough` option to forward `!command` input directly to the system shell.
- Persistent command history via `hist_file`.
- `Build.PL` for distribution build and dependency management.
- `META.yml` and `MANIFEST` for CPAN packaging.
- Full POD documentation including constructor args, methods, built-in commands,
  and tab completion behaviour.
- Test suite covering `validate_args` croak paths, construction sanity checks,
  and `_tab_complete` behaviour.
