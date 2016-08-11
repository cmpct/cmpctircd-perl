#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
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
    # [2016-08-08 15:10:45] m_uid(): new user on `irc.cmpct.info': irc.cmpct.info
    # [2016-08-08 15:10:45] user_add(): user (user@127.0.0.1) -> irc.cmpct.info
    # [2016-08-08 15:10:45] <- :00AAAAAAC NOTICE 0 :Services are presently running in debug mode, attached to a console. You should take extra caution when utilizing your services passwords.
    # [2016-08-08 15:10:45] -> :042 EOS
    # TODO: that
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
    $socket->write(":042 UID $sNick $sHop $sTime $sUser $sHost $sUID $sServiceStamp $sUmodes $sVirtHost $sCloakHost $sIP $sGECOS\r\n");
}

sub checkTimeout {}
sub disconnect {}

1;
