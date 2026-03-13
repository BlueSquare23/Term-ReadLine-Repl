# NAME

Term::ReadLine::Repl - A batteries included interactive Term::ReadLine Repl module

# SYNOPSIS

```
    use Term::ReadLine::Repl;

    # A simple repl
    my $repl = Term::ReadLine::Repl->new(
        {
            name => 'myrepl',
            cmd_schema => {
                ls => { 
                    exec => sub {my @list = qw(a b c); print for @list},  # Coderef to custom function for cmd
                }
            }
        }
    );

    # A complete repl
    $repl = Term::ReadLine::Repl->new(
        {
            name => 'myrepl',
            prompt => '(%s)>',
            cmd_schema => {
                stats => { 
                    exec => \&get_stats,  # Coderef to function
                    args => [{
                        refresh => undef,
                        host => 'hostname',
                        guest => 'guestname',
                        list => 'host|guest',
                        cluster => undef,
                    }],
                },
            },
            passthrough => 1,  # Enable !command system passthrough
            hist_file => '/path/to/.hist_file',
            get_opts => \&arg_parse  # Coderef to Getopt::Long parse function
            custom_logic => \&my_custom_loop_ctrl  # Coderef to custom logic run mid repl loop
        }
    );

    $repl->run();
```

# DESCRIPTION

## Overview

## Methods

- `new($args)`

    Returns built term object based on user supplied args hashref.

- `run($args)`

    Launches interactive session for custom defined repl.

# AUTHORS

    Written by John R. Copyright (c) 2026

