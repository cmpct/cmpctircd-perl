#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
use IRCd::Packets;

package IRCd::Client;

sub new {
    my $class = shift;
    my $self = {
        'socket'   => shift,
        'ircd'     => shift,
        'config'   => shift,
        # ...
        'sentWelcome' => 0,
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

    $self->{socket}->{sock}->write(":$ircd->{host} 001 $self->{nick} :Welcome to the $ircd->{network} IRC Network $self->{nick}!$self->{ident}\@$self->{ip}\r\n");
    $self->{socket}->{sock}->write(":$ircd->{host} 002 $self->{nick} :Your host is $ircd->{host}, running version $ircd->{version}\r\n");
    $self->{socket}->{sock}->write(":$ircd->{host} 003 $self->{nick} :This server was created on 1/1/1970\r\n");

    # Write MOTD
    my $motd;
    open($motd, "<", "ircd.motd");
    my @motd = <$motd>;
    $self->{socket}->{sock}->write(":$ircd->{host} 375 $self->{nick} :- $ircd->{host} Message of the Day -\r\n");
    foreach(@motd) {
        $self->{socket}->{sock}->write(":$ircd->{host} 372 $self->{nick} :- " . $_ . "\r\n");
    }
    $self->{socket}->{sock}->write(":$ircd->{host} 376 $self->{nick} :End of /MOTD command.\r\n");
    close($motd);
    $self->{sentWelcome} = 1;
}

1;
