#!/usr/bin/perl
use strict;
use warnings;
no warnings "experimental::postderef"; # for older perls (<5.24)
use feature 'postderef';

use IRCd::Channel;
use IRCd::Constants;
use IRCd::Resolve;

package IRCd::Client::Packets;

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

    # NICK already in use
    if($client->{nick} ne $splitPacket[1]) {
        if($ircd->{clients}->{nick}->{$splitPacket[1]}) {
            $client->{log}->info("[$client->{nick}] NICK in use!");
            $socket->write(":$config->{host} " . IRCd::Constants::ERR_NICKNAMEINUSE . " * NICK :Nickname is already in use\r\n");
            return;
        }
    }
    delete $ircd->{clients}->{nick}->{$client->{nick}} if $client->{nick} ne "";
    # TODO: Check for invalid nick...
    $client->{nick} = $splitPacket[1];
    $socket->write(":$mask NICK :$client->{nick}\r\n");
    $client->{log}->debug("NICK: $client->{nick}");

    $ircd->{clients}->{nick}->{$client->{nick}} = $client;
    $client->sendWelcome() if($client->{ident} and !$client->{registered} and $client->{host});
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

    $client->{log}->debug("IDENT: $client->{ident}");
    $client->{log}->debug("REAL:  $client->{realname}");

    $client->sendWelcome() if($client->{nick} and !$client->{registered} and $client->{host});
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
            $client->{log}->debug("JOIN param didn't begin w/ a #\r\n");
            return;
        }
        $channelInput = $splitPacket[1];
        if($channelInput =~ /,/) {
            # Multiple targets
            my @splitPacket = split(",", $channelInput);
            my $i = 0;
            foreach(@splitPacket) {
                IRCd::Client::Packets::join($client, $_, 1);
                $i++;
                last if($i > $ircd->{maxtargets});
            }
            return;
        }
    }

    # Need a list of server channels
    if($ircd->{channels}->{$channelInput}) {
        $client->{log}->info("[$channelInput] Channel already exists.\r\n");
        # Have them "JOIN", announce to other users
        $ircd->{channels}->{$channelInput}->addClient($client);
    } else {
        $client->{log}->info("[$channelInput] Creating channel..\r\n");
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
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHCHANNEL . " $client->{nick} $target :No such nick/channel\r\n");
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
    $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_ENDOFWHO . " $client->{nick} $channel->{name} :End of /WHO list.\r\n");
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
    my $targetHost     = $targetClient->{host} // $targetClient->{ip};
    # XXX: Claims to be online since 1970.
    my $targetIdle     = time() - $client->{idle};
    # TODO: RPL_WHOISOPERATOR => 313,
    # TODO: ircops will see '.. actually connected from'
    my @presentChannels = ();
    $targetHost         = $targetClient->{cloak} if($targetClient->{modes}->{x}->has($targetClient));

    $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_WHOISUSER     . " $client->{nick} $targetNick $targetIdent $targetHost * :$targetRealName\r\n");
    foreach(values($ircd->{channels}->%*)) {
        if($_->{clients}->{$targetNick}) {
            push @presentChannels, $_->{name};
        }
    }
    if($targetClient == $client) {
        # TODO: when ircops are added, add an OR for them
        $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_WHOISHOST . " $client->{nick} $targetNick :is connecting from $targetClient->{ident}\@$targetClient->{host} $targetClient->{ip}\r\n");
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
    @splitPacket    = split(":", $quitReason);
    $quitReason     = $splitPacket[1];

    # TODO: Max length
    $client->disconnect(1, $quitReason);
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

    if($partReason // 0) {
        @splitPacket = split(":", $partReason);
        $partReason = $splitPacket[1];
    } else {
        $partReason = "";
    }

    if($ircd->{channels}->{$partChannel}) {
        $ircd->{channels}->{$partChannel}->part($client, $partReason);
    } else {
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHCHANNEL . " $client->{nick} $partChannel :No such nick/channel\r\n");
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

    # TODO: Validation, no such channel
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
        $user->write(":$mask PRIVMSG $user->{nick} :$realmsg\r\n");
    }
}
sub mode {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();
    my @split  = split(" ", $msg, 4);
    my $type   = "";
    my %argmodes = ();

    $type   = "user" if($split[1] !~ /^#/);
    $type   = "chan" if($split[1] =~ /^#/);
    if($type eq "user") {
        %argmodes = ();
        foreach(values($client->{modes}->%*)) {
            $argmodes{$_->{provides}} = 1 if($_->{hasparam});
        }
        my @modes           = split('', $split[2]);
        my @parameters      = split(' ', $split[3]);
        my $const           = 0;
        my $currentModifier = "";
        foreach(@modes) {
            if($_ eq "+") {
                $currentModifier = "+";
                next;
            } elsif($_ eq "-") {
                $currentModifier = "-";
                next;
            }
            $client->{log}->debug("[$client->{nick}] MODE: $currentModifier$_");
            if($client->{modes}->{$_}) {
                $client->{modes}->{$_}->grant($client,  $currentModifier, $_,  $parameters[$const] // undef, 0, 1)  if $currentModifier eq "+";
                $client->{modes}->{$_}->revoke($client, $currentModifier, $_,  $parameters[$const] // undef, 0, 1)  if $currentModifier eq "-";
                if($argmodes{$_}) {
                    $client->{log}->debug("[$client->{nick}] Need to find a handler for: MODE $currentModifier$_ $parameters[$const]");
                    $const++ if $argmodes{$_};
                } else {
                    $client->{log}->debug("[$client->{nick}] Need to find a handler for: MODE $currentModifier$_");
                }
            }
        }
    } elsif($type eq "channel") {
        # Lookup channel
        my $channel = $ircd->{channels}->{$split[1]};
        if(!$channel) {
            $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHCHANNEL . " $client->{nick} $split[1] :No such nick/channel\r\n");
            return;
        }
        if(@split < 3) {
            my $channelModes = $channel->getModeStrings("+");
            $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_CHANNELMODEIS . " $client->{nick} $split[1] $channelModes->{characters} $channelModes->{args}\r\n");
            $client->{log}->warn("[$client->{nick}] MODE $split[1] => $channelModes->{characters} $channelModes->{args}");
            return;
        }
        # $channel exists at this point
        %argmodes = ();
        foreach(values($channel->{modes}->%*)) {
            $argmodes{$_->{provides}} = 1 if($_->{hasparam});
        }
        my @modes           = split('', $split[2]);
        my @parameters      = split(' ', $split[3]);
        my $const           = 0;
        my $currentModifier = "";
        foreach(@modes) {
            if($_ eq "+") {
                $currentModifier = "+";
                next;
            } elsif($_ eq "-") {
                $currentModifier = "-";
                next;
            }
            $client->{log}->debug("[$client->{nick}] MODE: $currentModifier$_");
            if($channel->{modes}->{$_}) {
                $channel->{modes}->{$_}->grant($client,  $currentModifier, $_,  $parameters[$const] // undef, 0, 1)  if $currentModifier eq "+";
                $channel->{modes}->{$_}->revoke($client, $currentModifier, $_,  $parameters[$const] // undef, 0, 1)  if $currentModifier eq "-";
                if($argmodes{$_}) {
                    $client->{log}->debug("[$client->{nick}] Need to find a handler for: MODE $currentModifier$_ $parameters[$const]");
                    $const++ if $argmodes{$_};
                } else {
                    $client->{log}->debug("[$client->{nick}] Need to find a handler for: MODE $currentModifier$_");
                }
            }
        }
    }
}
sub ping {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();
    # XXX: Is this right?
    $socket->write("PONG " . time() . "\r\n");
}
sub pong {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();

    my @splitPacket = split(" ", $msg, 2);
    $splitPacket[1] =~ s/://;
    if($splitPacket[1] eq $client->{pingcookie}) {
        $client->{log}->info("[$client->{nick}] Resetting PING clock\r\n");
        $client->{waitingForPong} = 0;
        $client->{lastPong} = time();
    }
}

sub topic {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();

    my @splitPacket  = split(" ", $msg);
    my $topicChannel = $splitPacket[1];
    my $topicText    = $splitPacket[2] // "";

    if($topicText) {
        @splitPacket = split(":", $msg);
        $topicText   = $splitPacket[1];
    }

    if($ircd->{channels}->{$topicChannel}) {
        $ircd->{channels}->{$topicChannel}->topic($client, $topicText);
    } else {
        # XXX: This should actually be 'no such channel'?
        # XXX: Fix the PART handler too
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHCHANNEL . " $client->{nick} $topicChannel :No such nick/channel\r\n");
    }
}


##                          ##
##  Operator (+o) Commands  ##
##                          ##
sub kick {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();

    # Validation of various sorts
    my @splitPacket   = split(" ", $msg);
    my $targetChannel = $ircd->{channels}->{$splitPacket[1]};
    if(!$targetChannel) {
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHCHANNEL . " $client->{nick} $splitPacket[1] :No such nick/channel\r\n");
        return;
    }

    my $targetUser    = $splitPacket[2];
    my @kickSplit     = split(":", $msg);
    my $kickReason    = $kickSplit[1] // "Kicked.";
    $targetChannel->kick($client, $targetUser, $kickReason);
}


# :card.freenode.net 451 * :You have not registered
1;
