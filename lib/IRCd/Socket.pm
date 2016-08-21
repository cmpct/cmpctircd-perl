#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
package IRCd::Socket;

sub new {
    my $class = shift;
    my $self  = {
        'fd'     => shift,
        'sock'   => shift,
        'type'   => undef,
        'client' => undef,
    };
    bless $self, $class;
    return $self;
}

1;
