#!/usr/bin/perl
use strict;
use warnings;
no warnings "experimental::postderef"; # for older perls (<5.24)
use feature 'postderef';

use IRCd::Server::Packets;
use IRCd::Constants;

package IRCd::Server;

sub new {
    my ($class, %args) = @_;
    my $self = {
        'socket'         => $args{socket},
        'ircd'           => $args{ircd},
        'config'         => $args{config},
        'buffer'         => '',

        'idle'           => $args{idle}           // 0,
        'lastPong'       => $args{lastPong}       // time(),
        'waitingForPong' => $args{waitingForPong} // 0,
        'sentcaps'       => $args{sentcaps}       // 0,
        # sid?
    };
    $self->{log} = $self->{ircd}->{log};
    bless $self, $class;
    return $self;
}


sub parse {
    my $self = shift;
    my $msg  = shift;
    my $sock = shift;

    my @splitPacket = split(" ", $msg);

    # TODO: Modular system
    # Check if function exists, and if so, call it
    if (my $handlerRef = IRCd::Server::Packets->can(lc($splitPacket[0]))) {
        $handlerRef->($self, $msg);
    } else {
        # If client is a server, we'll receive packets like :SID cmd
        if(my $handlerRef = IRCd::Server::Packets->can(lc($splitPacket[1]))) {
            $handlerRef->($self, $msg);
        } else {
            $self->{log}->warn("UNHANDLED PACKET: " . $splitPacket[0]);
        }
    }
}

sub sync {
    my $self   = shift;
    my $socket = $self->{socket}->{sock};
    my $config = $self->{config};
    my $ircd   = $self->{ircd};

    # This method provides for the initial server burst
    foreach(keys($self->{ircd}->{clients}->{nick}->%*)) {
        $self->syncUser($_);
    }
    $socket->write(":042 EOS\r\n");
    # TODO: sync-on-join/quit/etc
    # TODO: sjoin
    # TODO: and join
}

sub syncUser {
    my $self   = shift;
    my $socket = $self->{socket}->{sock};
    my $config = $self->{config};
    my $ircd   = $self->{ircd};
    my $user   = shift;
    my $client = $self->{ircd}->{clients}->{nick}->{$user};
    
    return -1 if(!$client);
    my $sNick  = $client->{nick};
    my $sHop   = 0;
    my $sTime  = time();
    my $sUser  = $client->{ident};
    my $sHost  = $client->{ip};
    my $sUID   = $client->{uid} // 0;
    my $sServiceStamp = 0;
    my $sUmodes    = "+i";
    my $sVirtHost  = $client->{ip};
    my $sCloakHost = $client->{ip};
    my $sIP        = $client->{ip};
    my $sGECOS     = $client->{realname};
    # TODO: $self->{sid}
    $socket->write(":042 UID $sNick $sHop $sTime $sUser $sHost $sUID $sServiceStamp $sUmodes $sVirtHost $sCloakHost $sIP $sGECOS\r\n");
}

sub checkTimeout {}
sub disconnect {}

1;
