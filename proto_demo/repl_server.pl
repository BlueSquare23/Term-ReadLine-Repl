#!/usr/bin/env perl
use strict;
use warnings;

# Proto-powered server built on top of the real Term::ReadLine::Repl module.
#
# Term::ReadLine::Repl->run() owns an interactive readline event loop that
# can't accept binary proto messages.  So instead of calling run(), we
# construct the object (which validates the schema and injects built-ins),
# then drive $repl->{cmd_schema} ourselves with a proto event loop.
#
# The Perl module never had to change.  The proto layer is just a different
# way to feed commands into the same dispatch table.
#
# Wire format: each message is preceded by a 4-byte big-endian length prefix.

use lib '../lib';
use Term::ReadLine::Repl;
use Google::ProtocolBuffers;
use POSIX qw(strftime);

# ---------------------------------------------------------------------------
# Define the shared proto schema (inline proto2, compatible with repl_pb2.py)
# ---------------------------------------------------------------------------
Google::ProtocolBuffers->parse(q{
    package repl;

    message ReplRequest {
        optional string command = 1;
        repeated string args    = 2;
    }

    message ReplResponse {
        optional bool   success            = 1;
        optional string output             = 2;
        optional bool   should_exit        = 3;
        repeated string available_commands = 4;
    }
});

# ---------------------------------------------------------------------------
# Command schema — passed directly to Term::ReadLine::Repl->new().
# The 'help' key is extra metadata used by this server's help handler;
# Term::ReadLine::Repl ignores unknown keys so it does not interfere.
# ---------------------------------------------------------------------------
my $cmd_schema = {
    greet => {
        exec => sub {
            my @args = @_;
            my $name = $args[0] // 'World';
            return "Hello, $name!\n";
        },
        help => 'Greet someone.  Usage: greet [name]',
    },

    add => {
        exec => sub {
            my @args = @_;
            unless (@args) {
                return "Usage: add <num> <num> ...\n";
            }
            for my $n (@args) {
                return "Error: '$n' is not a number.\n" unless $n =~ /^-?\d+(\.\d+)?$/;
            }
            my $sum = 0;
            $sum += $_ for @args;
            return "Result: $sum\n";
        },
        help => 'Sum a list of numbers.  Usage: add <n> [n ...]',
    },

    upper => {
        exec => sub {
            my @args = @_;
            return "Usage: upper <text>\n" unless @args;
            return uc(join(' ', @args)) . "\n";
        },
        help => 'Uppercase text.  Usage: upper <text>',
    },

    reverse => {
        exec => sub {
            my @args = @_;
            return "Usage: reverse <text>\n" unless @args;
            return scalar(reverse join(' ', @args)) . "\n";
        },
        help => 'Reverse a string.  Usage: reverse <text>',
    },

    info => {
        exec => sub {
            my $time = strftime('%Y-%m-%d %H:%M:%S', localtime);
            return sprintf(
                "Server PID : %d\nPerl version: %s\nTime       : %s\n",
                $$, $], $time
            );
        },
        help => 'Show server info (PID, Perl version, time)',
    },
};

# ---------------------------------------------------------------------------
# Construct the actual Term::ReadLine::Repl object.
# This validates the schema and injects the built-in help/quit commands.
# We never call $repl->run() — we supply our own proto-driven event loop
# below — but $repl->{cmd_schema} is now the fully-prepared dispatch table.
# ---------------------------------------------------------------------------
my $repl = Term::ReadLine::Repl->new({
    name       => 'proto-demo',
    cmd_schema => $cmd_schema,
});

# ---------------------------------------------------------------------------
# Wire framing helpers
# ---------------------------------------------------------------------------
sub read_message {
    my $len_buf = '';
    my $got = read(STDIN, $len_buf, 4);
    return undef unless defined $got && $got == 4;

    my $len = unpack('N', $len_buf);
    my $data = '';
    $got = read(STDIN, $data, $len);
    return undef unless defined $got && $got == $len;

    return $data;
}

sub write_message {
    my ($fh, $data) = @_;
    print $fh pack('N', length($data)) . $data;
    $fh->flush();
}

# ---------------------------------------------------------------------------
# Build the set of user-visible command names once (for help / tab complete).
# $repl->{cmd_schema} already includes the injected built-ins (help, quit).
# ---------------------------------------------------------------------------
my @all_commands = sort keys %{ $repl->{cmd_schema} };

# ---------------------------------------------------------------------------
# Open a dedicated handle for proto output *before* we might redirect STDOUT
# ---------------------------------------------------------------------------
open(my $proto_out, '>&:raw', \*STDOUT) or die "Cannot dup STDOUT: $!";
$proto_out->autoflush(1);

# Perl's default STDOUT may buffer; we don't want that on the proto side.
STDOUT->autoflush(1);

# ---------------------------------------------------------------------------
# Main request/response loop
# ---------------------------------------------------------------------------
while (1) {
    my $raw = read_message();
    last unless defined $raw;

    my $req = Repl::ReplRequest->decode($raw);
    my $cmd  = $req->{command} // '';
    my @args = @{ $req->{args} // [] };

    my $response;

    if ($cmd eq 'quit' || $cmd eq 'exit') {
        $response = Repl::ReplResponse->encode({
            success     => 1,
            output      => "Goodbye!\n",
            should_exit => 1,
        });

    } elsif ($cmd eq 'help') {
        my $text = "Available commands:\n";
        for my $name (sort keys %{ $repl->{cmd_schema} }) {
            $text .= sprintf("  %-10s %s\n", $name, $repl->{cmd_schema}{$name}{help} // '');
        }
        $response = Repl::ReplResponse->encode({
            success            => 1,
            output             => $text,
            available_commands => \@all_commands,
        });

    } elsif (exists $repl->{cmd_schema}{$cmd} && defined $repl->{cmd_schema}{$cmd}{exec}) {
        # Dispatch through the actual Term::ReadLine::Repl object's schema.
        # Capture any stray prints from the exec coderef into $captured.
        my $captured = '';
        my $result;
        {
            open(my $cap, '>', \$captured) or die "Cannot capture output: $!";
            local *STDOUT = $cap;
            $result = eval { $repl->{cmd_schema}{$cmd}{exec}->(@args) };
        }

        if ($@) {
            $response = Repl::ReplResponse->encode({
                success => 0,
                output  => "Error executing '$cmd': $@\n",
            });
        } else {
            # Prefer the return value; fall back to whatever was printed.
            my $output = (defined $result && length $result) ? $result : $captured;
            $response = Repl::ReplResponse->encode({
                success => 1,
                output  => $output,
            });
        }

    } else {
        my $msg = $cmd
            ? "Unknown command '$cmd'.  Type 'help' for options.\n"
            : "Empty command received.\n";
        $response = Repl::ReplResponse->encode({
            success => 0,
            output  => $msg,
        });
    }

    write_message($proto_out, $response);
}
