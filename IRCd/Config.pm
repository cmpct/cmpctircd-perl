#!/usr/bin/perl
use strict;
use warnings;
no warnings "experimental::postderef"; # for older perls (<5.24)
use feature 'postderef';

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
        'requirepong' => undef,
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
        $self->{usermodes}   = $xmlRef->{'usermodes'};
        $self->{cloak_keys}  = $xmlRef->{'cloak'}->{'key'};
        $self->{hidden_host} = $xmlRef->{'cloak'}->{'hiddenhost'};
        $self->{socketprovider} = $xmlRef->{'sockets'}->{'provider'};
        $self->{requirepong} = $xmlRef->{'advanced'}->{'requirepong'};
        $self->{dns}         = $xmlRef->{'advanced'}->{'dns'};
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
