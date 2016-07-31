#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
use IRCd::Packets;
use IRCd::Constants;

package IRCd::Client;

sub new {
    my $class = shift;
    my $self = {
        'socket'   => shift,
        'ircd'     => shift,
        'config'   => shift,
        # ...
        'sentWelcome' => 0,
        'idle'        => 0,
        'server'      => undef,

    };
    bless $self, $class;
    return $self;
}

sub getMask {
    my $self = shift;
    return $self->{nick} . '!' . $self->{ident} . '@' . $self->{ip};
}

sub parse {
    my $self = shift;
    my $msg  = shift;
    my $sock = shift;

    my @splitPacket = split(" ", $msg);

    # Check if function exists, and if so, call it
    if (my $handlerRef = IRCd::Packets->can(lc($splitPacket[0]))) {
        $handlerRef->($self, $msg);
    } else {
        print "UNHANDLED PACKET: " . $splitPacket[0] . "\r\n";
    }
}

sub sendWelcome {
    my $self = shift;
    my $ircd = $self->{ircd};
    $self->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::RPL_WELCOME  . " $self->{nick} :Welcome to the $ircd->{network} IRC Network $self->{nick}!$self->{ident}\@$self->{ip}\r\n");
    $self->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::RPL_YOURHOST . " $self->{nick} :Your host is $ircd->{host}, running version $ircd->{version}\r\n");
    $self->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::RPL_CREATED  . " $self->{nick} :This server was created on 1/1/1970\r\n");

    # Write MOTD
    my $motd;
    open($motd, "<", "ircd.motd");
    my @motd = <$motd>;
    $self->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::RPL_MOTDSTART . " $self->{nick} :- $ircd->{host} Message of the Day -\r\n");
    $self->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::RPL_MOTD      . " $self->{nick} :- " . $_ . "\r\n") foreach(@motd);
    $self->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::RPL_ENDOFMOTD . " $self->{nick} :End of /MOTD command.\r\n");
    close($motd);
    $self->{sentWelcome} = 1;
}

1;
