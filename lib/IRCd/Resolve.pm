#!/usr/bin/perl
use strict;
use warnings;
no warnings "experimental::postderef"; # for older perls (<5.24)
use feature 'postderef';

package IRCd::Resolve;

sub new {
    my $class = shift;
    if($ircd->{dns}) {
        require Net::DNS;
    } else {
        return;
    }
    my $self  = {
        'resolver'    => Net::DNS::Resolver->new,
        'ircd'        => shift,
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
    return  0 if(!$self->{resolver}->bgisready($socket));
    my $packet = $self->{resolver}->bgread($socket);
    return  0 if(!$packet);
    return 'ERROR' if($self->{resolver}->errorstring ne "NOERROR");
    my $resolvedHost = join('.', $packet->{answer}->[0]->{ptrdname}->{label}->@*);
    return $resolvedHost;
}


1;
