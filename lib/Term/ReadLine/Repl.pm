use strict;
use warnings;

package Term::ReadLine::Repl;

=head1 NAME

Term::ReadLine::Repl - A batteries included interactive Term::ReadLine Repl module
    
=head1 SYNOPSIS

    use Term::ReadLine::Repl;

    # A simple repl
    my $repl = Term::ReadLine::Repl->new(
        {
            name => 'myrepl',
            cmd_schema => {
                ls => { 
                    exec => \&list_stuff,  # Coderef to custom function for cmd
                }
            }
     )   

    # A complete repl
    $repl = Term::ReadLine::Repl->new(
        {
            name => 'myrepl',
            prompt => '(%s)>',
            cmd_schema => {
                stats => { 
                    exec => \&get_stats,  # Coderef to function
#                    args => \@args,  # List of function arg names
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

=head1 DESCRIPTION

=head2 Overview


=head2 Methods

=cut

use Data::Dumper;
use JSON qw(encode_json decode_json);
use Term::ANSIColor;
use Term::ReadLine;

=item C<new($args)>

Returns built term object based on user supplied args hashref.

=cut

sub new {
    my ($class, $args) = @_;

    my $self = {
        name         =>  $args->{name} // 'repl',
        prompt       =>  defined $args->{prompt} ? sprintf $args->{prompt}, $args->{name} : '(repl)>',
        cmd_schema   =>  $args->{cmd_schema},
        passthrough  =>  $args->{passthrough} // 0,
        hist_file    =>  $args->{hist_file},
        get_opts     =>  $args->{get_opts},
        custom_logic =>  $args->{custom_logic},
    };
    
    bless $self, $class;

# TODO: Write this!
#    validate_args($args);

    return $self;
}

=item C<run($args)>

Launches interactive session for custom defined repl.

=cut

sub run {
    my ($self) = @_;

    my $term = Term::ReadLine->new('Simple Shell');
    my $attribs = $term->Attribs;

    $self->_read_history($term) if defined $self->{hist_file};

    print colored(sprintf("Welcome to $self->{name} shell!"), 'green underline italic bold'), "\n";
    print colored(sprintf("Type 'help' for more options, <TAB> to auto complete."), 'green bold'), "\n";

    # TODO: Put in its own method(s)
    # Tab completion.
    $attribs->{completion_function} = sub {
        my ($text, $line) = @_;

        # Don't auto complete on passthroughs.
        return () if $line =~ /^\!/;

        # Split the current line into words.
        my @words = split(/\s+/, $line);
        my @complete_words = @words;
        pop @complete_words unless $line =~ /\s$/;

        if (@words >= 1) {
            my $cmd = $words[0];
            my $arg_index = (scalar(@complete_words) - 1);  # -1 because first word is always $cmd
            
            if ($self->{cmd_schema}{$cmd}) {

                my $opt_arg_index = $arg_index -1;

                # If next word matches args key, go into optargs
                if (exists $self->{cmd_schema}{$cmd}{args}[$opt_arg_index]{$complete_words[-1]}) {
                    my $opt_arg = $self->{cmd_schema}{$cmd}{args}[$opt_arg_index]{$complete_words[-1]};
                    return "<$opt_arg>";
                }

                # Count number of opt args in command to subtract from $arg_index.
                my $num_opt_args=0;
                my @all_opt_args;
                for my $arg (@{$self->{cmd_schema}{$cmd}{args}}) {
                    for my $key (keys %{$arg}) {
                        my $value = $arg->{$key};
                        push @all_opt_args, $key if defined $value;
                    }
                }
                for my $word (@complete_words) {
                    for my $opt_arg (@all_opt_args) {
                        $num_opt_args++ if ($word eq $opt_arg);
                    }
                }
                $arg_index = $arg_index - $num_opt_args;

                my $args = @{$self->{cmd_schema}{$cmd}{args}}[$arg_index];
                my @keys = keys %{$args};
                return () unless @keys;
                return grep { /^\Q$text/ } @keys;
            }
        }

        # If we're completing the first word
        if (@words <= 1) {
            my $cmd = $words[0];
            my @cmds = keys %{$self->{cmd_schema}};
            return grep { /^\Q$text/ } @cmds;
        }

        # No completion For anything beyond second word.
        return ();
    };

    my $prompt = colored(sprintf("$self->{prompt} "), 'green');

    $|++;

    # Simple REPL loop.
    while (defined (my $input = $term->readline($prompt))) {
        chomp $input;
        last if ($input =~ 'exit|quit');

        if ($input =~ 'help') {
            $self->_help();
            next;
        }

        my @args = split(/\s+/, $input);

        # Command line passthrough.
        if ($self->{passthrough} && @args && $args[0] =~ /^\!/) {
            $args[0] =~ s/\!//g;
            system(@args);
            next;
        }

        if (defined $self->{get_opts}) {
            # TODO: Add validation to assert get_opts is a coderef or raise exception or croak.

            # Clobber ARGV for getopts parsing, doesn't matter because client
            # code parser will slurp args outta @ARGV again right away.
            @ARGV = @args;
            $self->{get_opts}->();
        }

        # Custom loop logic.
        # User custom function can return a hashref like the following.
        # { 
        #     action => next|last|undef,
        #     schema => $schema,  # Where schema is a hashref containing any changes your custom logic might make to cmd_schema.
        # }
        if (defined $self->{custom_logic}) {
            my $result = eval {
                $self->{custom_logic}->(\@args);
            };

            if (defined $result && ref $result eq 'HASH') {
                if (defined $result->{action}) {
                    next if $result->{action} eq 'next';
                    last if $result->{action} eq 'last';
                }
                if (defined $result->{schema}) {
                    $self->{cmd_schema} = $result->{schema};
                }
            }
        }

        my $cmd = shift @args;

        if (exists $self->{cmd_schema}{$cmd}) {
            $self->{cmd_schema}{$cmd}{exec}->(@args);
        } else {
            print "No such command '$cmd' run 'help' to see options\n";
        }
    }
    print "\n" . colored(sprintf("Goodbye!"), 'green bold underline italic'), "\n";
    $self->_save_history($term) if defined $self->{hist_file};
}

sub _help {
    my ($self) = @_;

    my $output;
    for my $cmd (keys %{$self->{cmd_schema}}) {
        $output .= "$cmd\n";
        for my $args (sort @{$self->{cmd_schema}{$cmd}{args}} ) {
            $output .= "    ";
            for my $arg (keys %{$args}) {
                my $opt = $args->{$arg};
                $output .= "$arg";
                $output .= defined $opt ? "=<$opt>, " : ", ";
            }
            substr($output, -1) = "";  # Remove trailing space
            substr($output, -1) = "";  # Remove trailing ,
            $output .= "\n";
        }
    }
    print "$output\n";
}

sub _read_history {
    my ($self, $term) = @_;

    if (-f $self->{hist_file}) {
        open my $fh, '<', $self->{hist_file} or warn "Couldn't read auto bal history file: $!";
        while (my $line = <$fh>) {
            chomp $line;
            $term->addhistory($line);
        }
        close $fh;
    }
}

sub _save_history {
    my ($self, $term) = @_;

    my $attribs = $term->Attribs;

    open my $fh, '>>', $self->{hist_file} or warn "Couldn't save auto bal history: $!";
    if ($term->ReadLine =~ /Gnu/) {
        for my $line ($term->GetHistory) {
            print $fh "$line\n";
        }
    } 
    close $fh;
}


=head1 AUTHORS

    Written by John R. Copyright (c) 2026
=cut

1;

