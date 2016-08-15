#!/usr/bin/perl
use strict;
use warnings;
use Net::DNS;

package IRCd::Resolve;

sub new {
    my $class = shift;
    my $self  = {
        'resolver' => Net::DNS::Resolver->new,
    };
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
    my $resolvedHost = join('.', $packet->{answer}->[0]->{ptrdname}->{label}->@*);
    return $resolvedHost;
}


1;
