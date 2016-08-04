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

        'sentWelcome'    => 0,
        'idle'           => 0,
        'lastPong'       => time(),
        'waitingForPong' => 0,
        'server'         => undef,

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

    # TODO: Modular system
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
    # TODO: Strip out blank lines?
    $self->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::RPL_MOTDSTART . " $self->{nick} :- $ircd->{host} Message of the Day -\r\n");
    $self->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::RPL_MOTD      . " $self->{nick} :- " . $_ . "\r\n") foreach(@motd);
    $self->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::RPL_ENDOFMOTD . " $self->{nick} :End of /MOTD command.\r\n");
    close($motd);
    $self->{sentWelcome} = 1;
}

sub checkTimeout {
    my $self   = shift;
    my $ircd   = $self->{ircd};
    my $mask   = $self->getMask();
    my $period = $self->{lastPong} + $ircd->{pingtimeout};
    if(time() > $period and !$self->{waitingForPong}) {
        # XXX: Send a proper cookie
        $self->{socket}->{sock}->write("PING :cookie\r\n");
        $self->{waitingForPong} = 1;
    }
    # XXX: What if  need to PONG straight away?
    if(time() > ($self->{lastPong} + ($ircd->{pingtimeout} * 2)) and $self->{waitingForPong}) {
        $self->disconnect(1, "Ping timeout");
    } else {
        return if(time() > $period);
    }
}

sub disconnect {
    my $self     = shift;
    my $ircd     = $self->{ircd};
    my $mask     = $self->getMask();
    my $graceful = shift // 0;
    my $reason   = shift // "Leaving.";
    # Callers are expected to handle the graceful QUIT, or any other
    # parting messages.
    if($graceful) {
        foreach my $chan (keys($ircd->{channels}->%*)) {
            $ircd->{channels}->{$chan}->quit($self, $reason);
        }
        $self->{socket}->{sock}->write(":$mask QUIT :$reason\r\n");
    }
    $self->{socket}->{sock}->close();
    delete $ircd->{clients}->{id}->{$self->{socket}->{fd}};
    delete $ircd->{clients}->{nick}->{$self->{nick}};
}

1;
