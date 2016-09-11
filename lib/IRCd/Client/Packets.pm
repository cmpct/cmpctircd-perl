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
    my $mask   = $client->getMask(1);

    # XXX: For supybot/limnoria
    # XXX: No idea why it sends it; it's not as if NICKs can have spaces
    $msg =~ s/://;
    my @splitPacket = split(" ", $msg);
    if(scalar(@splitPacket) < 2) {
        $socket->write(":$config->{host} " . IRCd::Constants::ERR_NEEDMOREPARAMS . " * NICK :Not enough parameters\r\n");
        return;
    }

    # NICK already in use
    if($client->{nick} ne $splitPacket[1]) {
        if(my $nickObj = $ircd->{clients}->{nick}->{lc($splitPacket[1])}) {
            if($nickObj ne $client) {
                $client->{log}->info("[$client->{nick}] NICK in use!");
                $socket->write(":$config->{host} " . IRCd::Constants::ERR_NICKNAMEINUSE . " * $splitPacket[1] :Nickname is already in use\r\n");
                return;
            }
        }
    }
    # Check for invalid nick
    if ($splitPacket[1] !~ /[A-Za-z{}\[\]_\\^|`][A-Za-z{}\[\]_\-\\^|`0-9]*/) {
        $socket->write(":$config->{host} " . IRCd::Constants::ERR_ERRONEUSNICKNAME . " * NICK :Erroneous nickname: Illegal characters\r\n");
        return;
    }
    # Notify channels of the change
    foreach(values($ircd->{channels}->%*)) {
        if($_->{clients}->{$client->{nick}}) {
            $_->sendToRoom($client, ":$mask NICK :$splitPacket[1]", 0);
            $_->{clients}->{$splitPacket[1]} = $client;
            delete $_->{clients}->{$client->{nick}};
        }
    }
    delete $ircd->{clients}->{nick}->{lc($client->{nick})} if $client->{nick} ne "";
    $client->{nick} = $splitPacket[1];
    $socket->write(":$mask NICK :$client->{nick}\r\n");
    $client->{log}->debug("NICK: $client->{nick}");

    $ircd->{clients}->{nick}->{lc($client->{nick})} = $client;
    $client->sendWelcome() if($client->{ident} and !$client->{registered} and $client->{host});
}
sub user {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask(1);

    my @splitPacket = split(" ", $msg);

    if(scalar(@splitPacket) < 4) {
        $socket->write(":$config->{host} " . IRCd::Constants::ERR_NEEDMOREPARAMS . " * USER :Not enough parameters\r\n");
        return;
    }

    # validate nick
    if ($splitPacket[1] !~ /[A-Za-z0-9_\-\.]/) {
        $socket->write("ERROR :Hostile username. Please use only 0-9 a-z A-Z _ - and . in your username.\r\n");
        $client->disconnect(1);
        return;
    }
    $client->{ident}    = $splitPacket[1];
    @splitPacket = split(":", $msg, 2);
    $client->{realname} = $splitPacket[1];

    $client->{log}->debug("[$client->{nick}] IDENT: $client->{ident}");
    $client->{log}->debug("[$client->{nick}] REAL:  $client->{realname}");

    $client->sendWelcome() if($client->{nick} and !$client->{registered} and $client->{host});
}
sub cap {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask(1);
    # XXX: stub
    $client->{log}->debug("[$client->{nick}] CAP not yet implemented");
}
sub join {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask(1);
    my $recurs = shift // 0;
    my @splitPacket;

    # XXX: For supybot/limnoria
    # XXX: No idea why it sends it; it's not as if NICKs can have spaces
    $msg =~ s/://;
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
        $channel->initModes($client, $ircd);
        $channel->addClient($client);
        # some modes won't apply without the user in the channel, so apply after adding client
        $ircd->{channels}->{$channelInput} = $channel;
    }

}
sub who {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask(1);

    # XXX: We need to parse ',' and the rest of that
    # XXX: But forget it for now.
    # XXX: Don't reveal +i users on the network.
    my @splitPacket = split(" ", $msg);
    my $target      = $splitPacket[1] // "";

    # Get the channel obj
    # XXX: support user targets (insp does)
    my $channel = $ircd->{channels}->{$target};
    if(!$channel) {
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHCHANNEL . " $client->{nick} $target :No such nick/channel\r\n");
        return;
    }

    # TODO: Check the WHO response vs libpurple
    # https://bitbucket.org/pidgin/main/src/1cf07b94c6ca44814ad456de985947be66a391c8/libpurple/protocols/irc/msgs.c?at=default&fileviewer=file-view-default#msgs.c-942
    foreach(values($channel->{clients}->%*)) {
        my $user = $_->{ident};
        my $host = $_->get_host(1);
        my $nick = $_->{nick};
        my $real = $_->{realname};
        # XXX: include '*' for ircop
        my $away = $_->{away} // '' ne '' ? "G" : "H";
        my $userSymbol = $channel->{privilege}->{$channel->getStatus($_)} // "";
        $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_WHOREPLY . " $client->{nick} $channel->{name} $user $host $config->{host} $nick $away$userSymbol :0 $real\r\n");
    }
    $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_ENDOFWHO . " $client->{nick} $channel->{name} :End of /WHO list.\r\n");
}
sub names {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask(1);

    # Targets?
    my @splitPacket = split(" ", $msg);
    my $target      = $splitPacket[1];

    # Get the channel obj
    my $channel = $ircd->{channels}->{$target};
    if(!$channel) {
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHCHANNEL . " $client->{nick} $target :No such nick/channel\r\n");
        return;
    }

    # TODO: Implement userhost-in-names (IRCv3)
    foreach(values($channel->{clients}->%*)) {
        my $nick       = $_->{nick};
        my $userSymbol = $channel->{privilege}->{$channel->getStatus($_)} // "";
        $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_NAMREPLY . " $client->{nick} = $channel->{name} :$userSymbol$nick\r\n");
    }
    $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_ENDOFNAMES . " $client->{nick} $channel->{name} :End of /NAMES list.\r\n");
}
sub whois {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask(1);
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
    my $targetHost     = $targetClient->get_host(1);
    my $targetIdle     = time() - $client->{idle};
    my @presentChannels = ();

    $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_WHOISUSER     . " $client->{nick} $targetNick $targetIdent $targetHost * :$targetRealName\r\n");
    foreach(values($ircd->{channels}->%*)) {
        if($_->{clients}->{lc($targetNick)}) {
            push @presentChannels, $_->{name};
        }
    }
    if($targetClient == $client or $client->{modes}->{o}->has($client)) {
        $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_WHOISHOST . " $client->{nick} $targetNick :is connecting from $targetClient->{ident}\@$targetClient->{host} $targetClient->{ip}\r\n");
    }
    $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_WHOISCHANNELS . " $client->{nick} $targetNick :" . CORE::join(' ', @presentChannels) . "\r\n") if @presentChannels >= 1;
    $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_WHOISSERVER   . " $client->{nick} $targetNick $client->{server} :$ircd->{desc}\r\n");
    $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_WHOISOPERATOR . " $client->{nick} $targetNick :is an IRC operator\r\n") if $targetClient->{modes}->{o}->has($targetClient);
    # we only state away if they are away
    if ($targetClient->{away} ne '') {
        $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_AWAY   . " $client->{nick} $targetNick :$targetClient->{away}\r\n");
    }
    # XXX: Some IRCds (ircd-hybrid) use 275?
    $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_WHOISSECURE   . " $client->{nick} $targetNick :is connected via TLS (secure line)\r\n") if($targetClient->{modes}->{z}->has($targetClient));
    $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_WHOISIDLE     . " $client->{nick} $targetNick $targetIdle $client->{signonTime} :seconds idle, signon time\r\n");
    $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_ENDOFWHOIS    . " $client->{nick} $targetNick :End of /WHOIS list\r\n");
}
sub quit {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask(1);

    my @splitPacket    = split(":", $msg, 2);
    my $quitReason     = $splitPacket[1];

    # TODO: Max length
    $client->disconnect(1, "Quit: " . $quitReason);
}
sub part {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask(1);

    # TODO: Need target support (recursion) here
    my @splitPacket = split(" ", $msg);
    my $partChannel = $splitPacket[1];

    @splitPacket   = split(":", $msg, 2);
    my $partReason = $splitPacket[1] // "";

    if($ircd->{channels}->{$partChannel}) {
        $ircd->{channels}->{$partChannel}->part($client, $partReason);
    } else {
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHCHANNEL . " $client->{nick} $partChannel :No such nick/channel\r\n");
    }
}
sub away {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};

    # the only param is the message itself
    my @splitPacket = split(":", $msg, 2);
    my $awayMessage  = $splitPacket[1] // '';

    $client->{away} = $awayMessage;

    if($awayMessage ne '') {
        $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_NOWAWAY . " $client->{nick} :You have been marked as being away\r\n");
    } else {
        $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_UNAWAY . " $client->{nick} :You are no longer marked as being away\r\n");
    }
}
sub privmsg {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask(1);

    my @splitPacket = split(" ", $msg, 3);
    my $target   = $splitPacket[1];
    my $realmsg  = $splitPacket[2];
    if($msg =~ /:/) {
        @splitPacket = split(":", $msg, 2);
        $realmsg = $splitPacket[1];
    }

    if($target =~ /^#/) {
        # Target was a channel
        my $channel = $ircd->{channels}->{$target};
        if(!$channel) {
            $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHCHANNEL . " $client->{nick} $target :No such nick/channel\r\n");
            return;
        }
        $channel->sendToRoom($client, ":$mask PRIVMSG $channel->{name} :$realmsg", 0);
    } else {
        my $user = $ircd->getClientByNick($target);
        if($user == 0) {
            $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHNICK . " $client->{nick} $target :No such nick/channel\r\n");
            return;
        }
        # Warn the sender if the user is idle
        if ($user->{away} ne '') {
            $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_AWAY . " $client->{nick} $target :$user->{away}\r\n");
        }
        # Send the message to the target user
        $user->write(":$mask PRIVMSG $user->{nick} :$realmsg\r\n");
    }
}
sub notice {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask(1);

    my @splitPacket = split(" ", $msg);
    my $target = $splitPacket[1];
    @splitPacket = split(":", $msg, 2);
    my $realmsg = $splitPacket[1];

    if($target =~ /^#/) {
        # Target was a channel
        my $channel = $ircd->{channels}->{$target};
        if(!$channel) {
            $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHCHANNEL . " $client->{nick} $target :No such nick/channel\r\n");
            return;
        }
        $channel->sendToRoom($client, ":$client->{nick} NOTICE $channel->{name} :$realmsg", 0);
    } else {
        my $user = $ircd->getClientByNick($target);
        if($user == 0) {
            $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHNICK . " $client->{nick} $target :No such nick/channel\r\n");
            return;
        }
        # Warn the sender if the user is idle
        if ($user->{away} ne '') {
            $socket->write(":$ircd->{host} " . IRCd::Constants::RPL_AWAY . " $client->{nick} $target :$user->{away}\r\n");
        }
        # Send the message to the target user
        $user->write(":$mask NOTICE $user->{nick} :$realmsg\r\n");
    }
}
sub mode {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask(1);
    my @split  = split(" ", $msg, 4);
    my $type   = "";
    my $force  = shift // 0;
    my %argmodes = ();

    $type   = "user"    if($split[1] !~ /^#/);
    $type   = "channel" if($split[1] =~ /^#/);
    if($type eq "user") {
        %argmodes = ();
        foreach(values($client->{modes}->%*)) {
            $argmodes{$_->{provides}} = 1 if($_->{hasparam});
        }
        if(@split eq 3 and $split[2] eq '') {
            my $userModes = $client->getModeStrings("+");
            $client->write(":$ircd->{host} " . IRCd::Constants::RPL_UMODEIS . " $client->{nick} $userModes->{characters} $userModes->{args}");
            $client->{log}->warn("[$client->{nick}] MODE $client->{nick} => $userModes->{characters} $userModes->{args}");
            return;
        }
        my @modes           = split('',  $split[2] // "");
        my @parameters      = split(' ', $split[3] // "");
        my $const           = 0;
        my $currentModifier = "";
        my $modeChars       = "";
        my $modeArgs        = "";
        my $modeString      = "";
        my $success         = 0;
        foreach(@modes) {
            if($_ eq "+") {
                $currentModifier = "+";
                $modeChars      .= $currentModifier;
                next;
            } elsif($_ eq "-") {
                $currentModifier = "-";
                $modeChars      .= $currentModifier;
                next;
            }
            $client->{log}->debug("[$client->{nick}] MODE: $currentModifier$_");
            if($client->{modes}->{$_}) {
                if($currentModifier eq '+' and ($success = $client->{modes}->{$_}->grant($client,  $currentModifier, $_,  $parameters[$const] // undef, $force, 0))) {
                    # Mode was successful, push it on the stack
                    $modeChars .= $_;
                    $modeArgs  .= $parameters[$const] . " " if($argmodes{$_});
                }
                if($currentModifier eq '-' and ($success = $client->{modes}->{$_}->revoke($client, $currentModifier, $_,  $parameters[$const] // undef, $force, 0))) {
                    # Mode was successful, push it on the stack
                    $modeChars .= $_;
                    $modeArgs  .= $parameters[$const] . " " if($argmodes{$_});
                }
                if($argmodes{$_}) {
                    $client->{log}->debug("[$client->{nick}] Need to find a handler for: MODE $currentModifier$_ $parameters[$const]");
                    $const++ if $argmodes{$_};
                } else {
                    $client->{log}->debug("[$client->{nick}] Need to find a handler for: MODE $currentModifier$_");
                }
                $success = 0;
            }
            $modeString = $modeChars . " " . $modeArgs;
            $client->write(":$mask MODE $client->{nick} $modeString") if($modeString ne "");
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
            if($channelModes->{args}) {
                $client->write(":$ircd->{host} " . IRCd::Constants::RPL_CHANNELMODEIS . " $client->{nick} $split[1] $channelModes->{characters} $channelModes->{args}");
            } else {
                $client->write(":$ircd->{host} " . IRCd::Constants::RPL_CHANNELMODEIS . " $client->{nick} $split[1] $channelModes->{characters}");
            }
            $client->write(":$ircd->{host} "  . IRCd::Constants::RPL_CREATIONTIME  . " $client->{nick} $channel->{name} " . time());
            $client->{log}->warn("[$client->{nick}] MODE $split[1] => $channelModes->{characters} $channelModes->{args}");
            return;
        }
        # $channel exists at this point
        %argmodes = ();
        foreach(values($channel->{modes}->%*)) {
            $argmodes{$_->{provides}} = 1 if($_->{hasparam});
        }
        my @modes           = split('',  $split[2] // "");
        my @parameters      = split(' ', $split[3] // "");
        my $const           = 0;
        my $currentModifier = "";
        my $modeChars       = "";
        my $modeArgs        = "";
        my $modeString      = "";
        my $success         = 0;
        $split[2] =~ s/://;
        # Special case for just +b (ban list)
        if($split[2] =~ /b/ and !$split[3]) {
            $client->{log}->debug("[$client->{nick}] Requested +b list for $split[1]");
            foreach(values($channel->{modes}->{b}->list()->%*)) {
                my $banMask = $_->mask();
                $client->write(":$ircd->{host} " . IRCd::Constants::RPL_BANLIST .  " $client->{nick} $channel->{name} $banMask $_->{setter} $_->{time}");
            }
            $client->write(":$ircd->{host} " . IRCd::Constants::RPL_ENDOFBANLIST . " $client->{nick} $channel->{name} :End of channel ban list");
            return;
        }
        foreach(@modes) {
            if($_ eq "+") {
                $currentModifier = "+";
                $modeChars      .= $currentModifier;
                next;
            } elsif($_ eq "-") {
                $currentModifier = "-";
                $modeChars      .= $currentModifier;
                next;
            }
            $client->{log}->debug("[$client->{nick}] MODE: $currentModifier$_");
            if($channel->{modes}->{$_}) {
                if($currentModifier eq '+' and ($success = $channel->{modes}->{$_}->grant($client,  $currentModifier, $_,  $parameters[$const] // undef, $force, 0))) {
                    # Mode was successful, push it on the stack
                    $modeChars .= $_;
                    $modeArgs  .= $parameters[$const] . " " if($argmodes{$_});
                }
                if($currentModifier eq '-' and ($success = $channel->{modes}->{$_}->revoke($client, $currentModifier, $_,  $parameters[$const] // undef, $force, 0))) {
                    # Mode was successful, push it on the stack
                    $modeChars .= $_;
                    $modeArgs  .= $parameters[$const] . " " if($argmodes{$_});
                }
                if($argmodes{$_}) {
                    $client->{log}->debug("[$client->{nick}] Need to find a handler for: MODE $currentModifier$_ $parameters[$const]");
                    $const++ if $argmodes{$_};
                } else {
                    $client->{log}->debug("[$client->{nick}] Need to find a handler for: MODE $currentModifier$_");
                }
                $success = 0;
            }
        }
        $modeString = $modeChars . " " . $modeArgs;
        $channel->sendToRoom($client, ":$mask MODE $channel->{name} $modeString") if($modeString ne "");
    }
}
sub userhost {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask(1);

    my @target       = split(" ", $msg);
    my $targetNick   = $target[1];
    my $away         = "";
    if(my $targetClient = $ircd->getClientByNick($targetNick)) {
        $away = "-" if($client->{away});
        $away = "+" if($client->{away});
        my $user = $targetClient->{ident};
        my $host = "";
        if($targetClient eq $client) {
            $host = $targetClient->get_host(0);
        } else {
            $host = $targetClient->get_host(1);
        }
        $client->write(":$ircd->{host} " . IRCd::Constants::RPL_USERHOST . " $client->{nick} $targetNick=$away$user\@$host");
    }

}
sub ping {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask(1);
    my @splitPacket = split(" ", $msg);
    $splitPacket[1] =~ s/://;
    $socket->write(":$ircd->{host} PONG $ircd->{host} :" . $splitPacket[1] . "\r\n");
}
sub pong {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask(1);

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
    my $mask   = $client->getMask(1);
    my $force  = shift // 0;

    my @splitPacket  = split(" ", $msg, 3);
    my $topicChannel = $splitPacket[1];
    my $topicText    = $splitPacket[2] // "";

    # Splitting on the colon is tempting, but some IRC clients and most IRCds
    # will take one without a colon, so handle both
    if($topicText && $topicText =~ /^:/) {
        @splitPacket = split(":", $msg, 2);
        $topicText   = $splitPacket[1];
    }

    if($ircd->{channels}->{$topicChannel}) {
        $ircd->{channels}->{$topicChannel}->topic($client, $topicText, $force);
    } else {
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
    my $mask   = $client->getMask(1);

    # Validation of various sorts
    my @splitPacket   = split(" ", $msg);
    my $targetChannel = $ircd->{channels}->{$splitPacket[1]};
    if(!$targetChannel) {
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHCHANNEL . " $client->{nick} $splitPacket[1] :No such nick/channel\r\n");
        return;
    }

    my $targetUser    = $splitPacket[2];
    my @kickSplit     = split(":", $msg, 2);
    my $kickReason    = $kickSplit[1] // "Kicked.";
    $targetChannel->kick($client, $targetUser, $kickReason);
}

sub motd {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask(1);

    $client->motd();
  }

sub rules {
    my $client = shift;
    my $msg    = shift;
    my $socket = $client->{socket}->{sock};
    my $config = $client->{config};
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask(1);

    $client->rules();
}

# :card.freenode.net 451 * :You have not registered
1;
