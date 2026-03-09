#!/usr/bin/env perl

use warnings;
use strict;

use Data::Dumper;

use lib './lib';


use Term::ReadLine::Repl;


sub get_stats {
    my $arg = shift;

    if ($arg eq 'a') {
        print "a\n";
        return;
    }
    print "1,2,3,4,5\n";
}

my $term = Term::ReadLine::Repl->new(
    {
        name => 'myrepl',
        prompt => '(%s)>',
        cmd_schema => {
            stats => {
                exec => \&get_stats,
                args => [{
                    refresh => undef,
                    host => 'hostname',
                    guest => 'guestname',
                    list => 'host|guest',
                    cluster => undef,
                }, 
                { 
                    test => undef,
                    another => undef,
                }],
            },
            xml => {
                exec => \&list_items,
                args => [{refresh=>undef, 'cluster|host'=>undef, 'hostname'=>undef}],
            }
        },
        passthrough => 1,  # Enable !command system passthrough
    }
);

print Dumper $term;

$term->run();


