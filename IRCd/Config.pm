#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
package IRCd::Config;

sub new {
    my $class = shift;
    my $self = {
        'filename' => shift,
        'ip' => undef,
        'port' => undef,
        'version' => 0.1,

        # ircd obj
        'channels' => {},
    };
    bless $self, $class;
    return $self;
}

sub parse {
    my $self = shift;
    do{
        use XML::Simple;
        my $parse  = XML::Simple->new();
        my $xmlRef = $parse->XMLin("ircd.xml");

        $self->{ip}      = $xmlRef->{'server'}->{'ip'};
        $self->{port}    = $xmlRef->{'server'}->{'port'};
        $self->{host}    = $xmlRef->{'ircd'}->{'host'};
        $self->{network} = $xmlRef->{'ircd'}->{'network'};
    }
}

sub getClientByNick {
    my $self = shift;

}

1;
