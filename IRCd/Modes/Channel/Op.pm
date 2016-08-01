#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;

package IRCd::Modes::Channel::Op;

sub new {
    my $class = shift;
    my $self  = {
        'name'     => 'op',
        'provides' => 'o',
        'desc'     => 'Provides the +o (op) mode for moderating a channel.',
        'affects'  => {},
        'channel'  => shift,
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
sub revoke {
    my $self   = shift;
    my $client = shift;
    delete $self->{affects}->{$client};
}
sub has {
    my $self   = shift;
    my $client = shift;
    return 1 if($self->{affects}->{$client});
    return 0;
}


1;
