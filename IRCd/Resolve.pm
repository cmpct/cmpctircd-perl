#!/usr/bin/perl
use strict;
use warnings;
no warnings "experimental::postderef"; # for older perls (<5.24)
use feature 'postderef';

use Net::DNS;

package IRCd::Resolve;

sub new {
    my $class = shift;
    my $self  = {
        'resolver' => Net::DNS::Resolver->new,
    };
    # TODO: A cache?
    bless $self, $class;
    return $self;
}

sub fire {
    my $self   = shift;
    my $ip     = shift;
    my $socket = $self->{resolver}->bgsend($ip);
    return $socket;
}

sub read {
    my $self   = shift;
    my $socket = shift;
    return if(!$self->{resolver}->bgisready($socket));
    my $packet = $self->{resolver}->bgread($socket);
    return if(!$packet);
    return -1 if($self->{resolver}->errorstring ne "NOERROR");
    my $resolvedHost = join('.', $packet->{answer}->[0]->{ptrdname}->{label}->@*);
    return $resolvedHost;
}


1;
