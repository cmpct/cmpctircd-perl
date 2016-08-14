#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;

use IRCd::Sockets::Epoll;
use IRCd::Sockets::Select;

package IRCd::Config;

sub new {
    my $class = shift;
    my $self = {
        'filename' => shift,
        # <ircd>
        'host'     => undef,
        'network'  => undef,
        'desc'     => undef,
        # <server>
        'ip'       => undef,
        'port'     => undef,
        # <sockets>
        'provider' => undef,
        # <advanced>
        'pingtimeout' => undef,
        'maxtargets'  => undef,
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

        $self->{ip}          = $xmlRef->{'server'}->{'ip'};
        $self->{port}        = $xmlRef->{'server'}->{'port'};
        $self->{host}        = $xmlRef->{'ircd'}->{'host'};
        $self->{network}     = $xmlRef->{'ircd'}->{'network'};
        $self->{desc}        = $xmlRef->{'ircd'}->{'desc'};
        $self->{socketprovider} = $xmlRef->{'sockets'}->{'provider'};
        $self->{pingtimeout} = $xmlRef->{'advanced'}->{'pingtimeout'};
        $self->{maxtargets}  = $xmlRef->{'advanced'}->{'maxtargets'};
    }
}

sub getSockProvider {
    my $self     = shift;
    my $listener = shift;
    # Honour their preference until we can't.
    my $OS = $^O;
    return IRCd::Sockets::Epoll->new($listener)  if($self->{socketprovider} eq "epoll" and $OS eq 'linux');
    return IRCd::Sockets::Select->new($listener) if($self->{socketprovider} eq "select");
}

1;
