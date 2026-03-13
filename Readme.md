# NAME

Term::ReadLine::Repl - A batteries included interactive Term::ReadLine REPL module

# SYNOPSIS

    use Term::ReadLine::Repl;

    # A simple repl
    my $repl = Term::ReadLine::Repl->new(
        {
            name       => 'myrepl',
            cmd_schema => {
                ls => {
                    exec => sub { my @list = qw(a b c); print for @list },
                },
            },
        }
    );

    # A complete repl
    $repl = Term::ReadLine::Repl->new(
        {
            name       => 'myrepl',
            prompt     => '(%s)>',
            cmd_schema => {
                stats => {
                    exec => \&get_stats,
                    args => [
                        {
                            refresh => undef,
                            host    => 'hostname',
                            guest   => 'guestname',
                            list    => 'host|guest',
                            cluster => undef,
                        }
                    ],
                },
            },
            passthrough  => 1,
            hist_file    => '/path/to/.hist_file',
            get_opts     => \&arg_parse,
            custom_logic => \&my_custom_loop_ctrl,
        }
    );

    $repl->run();

# DESCRIPTION

`Term::ReadLine::Repl` provides a simple framework for building interactive
command-line REPLs (Read-Eval-Print Loops) on top of [Term::ReadLine](https://metacpan.org/pod/Term%3A%3AReadLine). It
handles tab completion, command history, a built-in help system, and optional
passthrough to shell commands, so you can focus on defining your commands
rather than plumbing the terminal interaction.

# CONSTRUCTOR

- `new(\%args)`

    Creates and returns a new `Term::ReadLine::Repl` object. Accepts a hashref
    with the following keys:

    - `name` (required)

        A string used as the name of the REPL, displayed in the welcome message and
        optionally interpolated into the prompt via `%s`.

    - `cmd_schema` (required)

        A hashref defining the available commands. Each key is a command name, and
        its value is a hashref with the following keys:

        - `exec` (required)

            A coderef that is called when the command is invoked. Any arguments supplied
            on the command line (after the command name) are passed to the coderef.

        - `args` (optional)

            An arrayref of hashrefs describing the command's arguments for tab completion.
            Each hashref maps an argument name to either `undef` (flag, no value expected)
            or a string describing the expected value (used as a completion hint).

    - `prompt` (optional)

        A `sprintf`-style format string for the prompt. `%s` is replaced with the
        REPL name. Defaults to `(repl)`>.

    - `passthrough` (optional)

        When set to a true value, any input beginning with `!` is passed directly to
        the system shell. For example, `!ls -la` would run `ls -la`. Defaults to `0`.

    - `hist_file` (optional)

        Path to a file used for persistent command history. History is loaded on
        startup and saved on exit. If not specified, history is not persisted.

    - `get_opts` (optional)

        A coderef to a [Getopt::Long](https://metacpan.org/pod/Getopt%3A%3ALong) parsing function. When provided, it is called
        before each command dispatch with `@ARGV` populated from the current input line.

    - `custom_logic` (optional)

        A coderef invoked on each loop iteration before command dispatch. Receives an
        arrayref of the parsed input tokens. May return a hashref with the following
        optional keys:

        - `action`

            Set to `'next'` to skip to the next loop iteration, or `'last'` to exit
            the REPL loop.

        - `schema`

            A replacement `cmd_schema` hashref to swap in for subsequent iterations.

# METHODS

- `run()`

    Launches the interactive REPL session. Prints a welcome message, then enters
    the read-eval-print loop until the user types `quit`, `exit`, or `EOF`.
    Saves history on exit if `hist_file` was configured.

- `validate_args(\%args)`

    Validates the constructor argument hashref. Croaks with a descriptive message
    if any required arguments are missing or if any values have an unexpected type.
    Called automatically by `new()`.

# BUILT-IN COMMANDS

The following commands are automatically added to every REPL:

- `help`

    Prints all available commands and their arguments.

- `quit` / `exit`

    Exits the REPL session.

# TAB COMPLETION

Tab completion is provided automatically for command names and their defined
arguments. Completions are driven by the `args` key in each command's schema.
Passthrough commands (those beginning with `!`) are excluded from completion.

# AUTHORS

Written by John R. Copyright (c) 2026
