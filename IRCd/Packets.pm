#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
use feature 'postderef';
use IRCd::Channel;
use IRCd::Constants;
package IRCd::Packets;

sub nick {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();

    my @splitPacket = split(" ", $msg);
    if(scalar(@splitPacket) < 2) {
        $socket->write(":$config->{host} " . IRCd::Constants::ERR_NEEDMOREPARAMS . " * NICK :Not enough parameters\r\n");
        return;
    }

    # NICK already in use?
    if($client->{nick} ne $splitPacket[1]) {
        if($ircd->{clients}->{nick}->{$splitPacket[1]}) {
            print "NICK in use!\r\n";
            $socket->write(":$config->{host} " . IRCd::Constants::ERR_NICKNAMEINUSE . " * NICK :Nickname is already in use\r\n");
            return;
        }
    }
    delete $ircd->{clients}->{nick}->{$client->{nick}} if $client->{nick} ne "";
    # TODO: Check for invalid nick...
    $client->{nick} = $splitPacket[1];
    $socket->write(":$mask NICK :$client->{nick}\r\n");
    print "NICK: $client->{nick}", "\r\n";

    $ircd->{clients}->{nick}->{$client->{nick}} = $client;
    $client->sendWelcome() if($client->{ident} and !$client->{sentWelcome});
}
sub user {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();

    my @splitPacket = split(" ", $msg);

    if(scalar(@splitPacket) < 4) {
        $socket->write(":$config->{host} " . IRCd::Constants::ERR_NEEDMOREPARAMS . " * USER :Not enough parameters\r\n");
        return;
    }
    $client->{ident}    = $splitPacket[1];
    @splitPacket = split(":", $msg);
    $client->{realname} = $splitPacket[1];

    print "IDENT: $client->{ident}", "\r\n";
    print "REAL:  $client->{realname}", "\r\n";

    $client->sendWelcome() if($client->{nick} and !$client->{sentWelcome});
}
sub join {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();
    my $recurs = shift // 0;
    my @splitPacket;

    $client->{idle} = time();
    my $channelInput = $msg;

    if($recurs == 0) {
        @splitPacket = split(" ", $msg);
        if(scalar(@splitPacket) < 2) {
            $socket->write(":$config->{host} " . IRCd::Constants::ERR_NEEDMOREPARAMS . " * JOIN :Not enough parameters\r\n");
            return;
        }
        if($splitPacket[1] !~ /^#/){
            print "JOIN param didn't begin w/ a #\r\n";
            return;
        }
        $channelInput = $splitPacket[1];
        if($channelInput =~ /,/) {
            # Multiple targets
            my @splitPacket = split(",", $channelInput);
            my $i = 0;
            foreach(@splitPacket) {
                IRCd::Packets::join($client, $_, 1);
                $i++;
                last if($i > $ircd->{maxTargets});
            }
            return;
        }
    }

    # Need a list of server channels
    if($ircd->{channels}->{$channelInput}) {
        print "Channel already exists.\r\n";
        # Have them "JOIN", announce to other users
        $ircd->{channels}->{$channelInput}->addClient($client);
    } else {
        print "Creating channel..\r\n";
        my $channel = IRCd::Channel->new($channelInput);
        $channel->addClient($client);
        $ircd->{channels}->{$channelInput} = $channel;
    }

}
sub who {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();

    # XXX: We need to parse ',' and the rest of that
    # XXX: But forget it for now.
    # XXX: Don't reveal +i users on the network.
    my @splitPacket = split(" ", $msg);
    my $target      = $splitPacket[1];

    # Get the channel obj
    my $channel = $ircd->{channels}->{$target};
    if(!$channel) {
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHCHANNEL . " $client->{nick} $channel->{name} :No such nick/channel\r\n");
        return;
    }

    # TODO: Check the WHO response vs libpurple
    # https://bitbucket.org/pidgin/main/src/1cf07b94c6ca44814ad456de985947be66a391c8/libpurple/protocols/irc/msgs.c?at=default&fileviewer=file-view-default#msgs.c-942
    foreach(values($channel->{clients}->%*)) {
        my $user = $_->{ident};
        my $host = $_->{ip};
        my $nick = $_->{nick};
        my $real = $_->{realname};
        $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_WHOREPLY . " $client->{nick} $channel->{name} $user $host $config->{host} $nick H :0 $real\r\n");
    }
    $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_ENDOFWHO . " $client->{nick} :End of /WHO list.\r\n");
}
sub whois {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();
    my @splitMessage = split(" ", $msg);
    my $target = $splitMessage[1];
    my $targetNick    = $splitMessage[1];
    my $targetClient  = $ircd->getClientByNick($targetNick);
    if($targetClient == 0) {
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHNICK . " $client->{nick} $target :No such nick/channel\r\n");
        return;
    }
    my $targetIdent    = $targetClient->{ident};
    my $targetRealName = $targetClient->{realname};
    my $targetHost     = $targetClient->{ip};
    # XXX: Claims to be online since 1970.
    my $targetIdle     = time() - $client->{idle};
    # TODO: RPL_WHOISOPERATOR => 313,
    my @presentChannels = ();
    $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_WHOISUSER     . " $client->{nick} $targetNick $targetIdent $targetHost * :$targetRealName\r\n");
    foreach(values($ircd->{channels}->%*)) {
        if($_->{clients}->{$targetNick}) {
            push @presentChannels, $_->{name};
        }
    }
    $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_WHOISCHANNELS . " $client->{nick} $targetNick :" . CORE::join(' ', @presentChannels) . "\r\n") if @presentChannels >= 1;
    $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_WHOISSERVER   . " $client->{nick} $targetNick $client->{server} :$ircd->{desc}\r\n");
    $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_WHOISIDLE     . " $client->{nick} $targetNick $targetIdle :seconds idle\r\n");
    $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_ENDOFWHOIS    . " $client->{nick} $targetNick :End of /WHOIS list\r\n");
}
sub quit {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();

    my @splitPacket = split(" ", $msg);
    my $quitReason  = $splitPacket[1];
    @splitPacket = split(":", $quitReason);
    $quitReason = $splitPacket[1];

    # TODO: Max length
    foreach my $chan (keys($ircd->{channels}->%*)) {
        $ircd->{channels}->{$chan}->quit($client, $quitReason);
    }
    # XXX: Let anyone who we're PMIng know? is that a thing?
}
sub part {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();

    $client->{idle} = time();
    # TODO: Need target support (recursion) here
    my @splitPacket = split(" ", $msg);
    my $partChannel = $splitPacket[1];
    my $partReason  = $splitPacket[2];
    @splitPacket = split(":", $partReason);
    $partReason = $splitPacket[1];

    if($ircd->{channels}->{$partChannel}) {
        $ircd->{channels}->{$partChannel}->part($client, $partReason);
    } else {
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $partChannel :You're not on that channel\r\n");
    }
}
sub privmsg {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();

    $client->{idle} = time();
    my @splitPacket = split(" ", $msg);
    my $target = $splitPacket[1];
    @splitPacket = split(":", $msg);
    my $realmsg = $splitPacket[1];

    if($target =~ /^#/) {
        # Target was a channel
        my $channel = $ircd->{channels}->{$target};
        $channel->sendToRoom($client, ":$client->{nick} PRIVMSG $channel->{name} :$realmsg", 0);
    } else {
        my $user = $ircd->getClientByNick($target);
        if($user == 0) {
            $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHNICK . " $client->{nick} $target :No such nick/channel\r\n");
            return;
        }
        # Send the message to the target user
        $user->{socket}->{sock}->write(":$mask PRIVMSG $user->{nick} :$realmsg\r\n");
    }
}

# :card.freenode.net 451 * :You have not registered
1;
