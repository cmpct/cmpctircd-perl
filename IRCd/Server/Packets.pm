#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
use feature 'postderef';
use IRCd::Constants;

package IRCd::Server::Packets;

sub pass {
    my $server = shift;
    my $msg    = shift;
    my $socket = $server->{socket}->{sock};
    my $config = $server->{config};
    my $ircd   = $server->{ircd};
    my @splitMessage = split(" ", $msg);
    $server->{log}->debug("[$server->{name}] Got a password!");
    # ACK it for now
    $socket->write("PASS :$splitMessage[1]\r\n");
}

sub protoctl {
    my $server = shift;
    my $msg    = shift;
    my $socket = $server->{socket}->{sock};
    my $config = $server->{config};
    my $ircd   = $server->{ircd};
    $server->{log}->debug("[$server->{name}] Got a PROTOCTL!");
    # https://www.unrealircd.org/docs/Server_protocol:PROTOCTL_command
    # We're going for UnrealIRCd compat. for now
    # Parse all the tokens...
    my @splitPacket = split(" ", $msg);
    foreach(@splitPacket) {
        # my ($a, $b, $c) = @_;
        next if($_ =~ qw/PROTOCTL/);
        #print "Got token: $_\r\n";
        # ESVID?
        $server->{caps}->{$_} = 1 if($_ eq "NICKV2");
        $server->{caps}->{$_} = 1 if($_ eq "NICKIP");
        $server->{caps}->{$_} = 1 if($_ eq "SJOIN");
        $server->{caps}->{$_} = 1 if($_ eq "SJ3");
        $server->{caps}->{$_} = 1 if($_ eq "NOQUIT");
        $server->{caps}->{$_} = 1 if($_ eq "TKLEXT");
        $server->{caps}->{$_} = 1 if($_ eq "MLOCK");
        if($_ =~ /^EAUTH=/) {
            $_ =~ s/EAUTH=//;
            $server->{name} = $_;
            # We've got a server name
            # Now parse any other tokens
            return if($_ !~ /,/);
            my @splitEAUTH = split(",", $_);
            # XXX: Need to parse SID, etc for unreal linking
        }
        if($_ =~ /^SID=/) {
            $_ =~ s/SID=//;
            $server->{sid} = $_;
        }
    }
    $server->{log}->debug("Server name: $server->{name}") if($server->{name} // 0);
    $server->{log}->debug("Server SID:  $server->{sid}")  if($server->{sid}  // 0);

    # "I'll show you what I'm capable of!"
    # (capability negotiation)
    return if($server->{sentcaps});
    $socket->write("PROTOCTL NOQUIT NICKv2 SJOIN SJOIN2 UMODE2 VL SJ3 TKLEXT TKLEXT2 NICKIP ESVID\r\n");
    $socket->write("PROTOCTL CHANMODES=beI,kLf,l,psmntirzMQNRTOVKDdGPZSCc NICKCHARS= SID=042 MLOCK TS=1470591491 EXTSWHOIS\r\n");
    $socket->write("SERVER $ircd->{host} 1 :U4000-Fhin6OoEM-042 $ircd->{desc}\r\n");
    $socket->write("NETINFO 0 " . time() . " 4000 MD5:2978762380c4474b73dd6c51aed84815 0 0 0 :cmpct\r\n");
    $server->{sentcaps} = 1;

    # Sync
    $server->sync();
}


sub server {
    my $server = shift;
    my $msg    = shift;
    my $socket = $server->{socket}->{sock};
    my $config = $server->{config};
    my $ircd   = $server->{ircd};

}

sub ping {
    my $server = shift;
    my $msg    = shift;
    my $socket = $server->{socket}->{sock};
    my $config = $server->{config};
    my $ircd   = $server->{ircd};
    my @splitPacket = split(" ", $msg);
    $splitPacket[1] =~ s/://;
    #:irc.cmpct.info PONG irc.cmpct.info :00A
    $socket->write(":$ircd->{host} PONG $ircd->{host} :$splitPacket[1]\r\n");
}

sub uid {
    my $server = shift;
    my $msg    = shift;
    my $socket = $server->{socket}->{sock};
    my $config = $server->{config};
    my $ircd   = $server->{ircd};

    my @splitPacket = split(" ", $msg);
    # Yes, there are meant to be two of these.
    shift @splitPacket;
    shift @splitPacket;


    # Receiving an introduction
    # https://www.unrealircd.org/docs/Server_protocol:UID_command
    my ($pNickname,     $pHopCount, $pTimestamp,   $pUser, $pHost, $pUID,
        $pServiceStamp, $pUmodes,   $pCloakedHost, $pIP,   $pGECOS)
    = @splitPacket;


    $server->{clients}->{uid}->{$pUID} = IRCd::Client->new(
        'socket' => $socket,
        'ircd'   => $ircd,
        'config' => $config,
        'uid'    => $pUID,
        'nick'   => $pNickname,
    );
    $server->{log}->info("Introducing: $pNickname!$pUser\@$pHost [$pUID]");
}

sub notice {
    my $server = shift;
    my $msg    = shift;
    my $socket = $server->{socket}->{sock};
    my $config = $server->{config};
    my $ircd   = $server->{ircd};

    my @splitPacket   = split(" ", $msg);
    my $source        = $splitPacket[0];
    my $target        = $splitPacket[2];
    my @splitMessage  = split(":", $msg);
    my $message       = $splitMessage[2];
    $source =~ s/://;
    # Do we need a findByUID?
    $source = $server->{clients}->{uid}->{$source};
    # Special case
    if($target eq "0") {
        foreach(values($ircd->{clients}->{nick}->%*)) {
            #print ":$source->{nick} NOTICE $_->{nick} :$splitMessage[2]\r\n";
            # XXX: @services.int is a nono
            $_->{socket}->{sock}->write(":$source->{nick}!$source->{nick}\@services.int NOTICE $_->{nick} :$splitMessage[2]\r\n");
        }
    }
}



1;
