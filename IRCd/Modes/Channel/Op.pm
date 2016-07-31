#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;

sub new {
    my $class = shift;
    my $self  = {
        'name'     => 'op'
        'provides' => 'o',
        'desc'     => 'Provides the +o (op) mode for moderating a channel.',
        affects    => (),
        channel    => shift,
    };
    bless $self, $class;
    return $self;
}

# XXX: Use this
# XXX: Levels?

sub grant {
    my $self   = shift;
    my $client = shift;
    $self->{affects}->{$client} = 1;
}
sub deop {
    my $self   = shift;
    my $client  = shift;
    delete $self->{affects}->{$client};
}


1;
