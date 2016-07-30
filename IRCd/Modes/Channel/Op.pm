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
        affects    => [],
        channel    => shift,
    };
    bless $self, $class;
    return $self;
}

# XXX: Use this
# XXX: Levels?

sub grant {
    my $self   = shift;
    my $client = shift
    push $self->{affects}->@*, $client;
}
sub deop {
    my $self   = shift;
    my $client  = shift;
    @{$self->{affects}} = grep { $_ != $client } @{$self->{affects}};
}


1;
