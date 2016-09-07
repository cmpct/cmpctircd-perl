#!/usr/bin/perl
use strict;
use warnings;
no warnings "experimental::postderef"; # for older perls (<5.24)
use feature 'postderef';

use IRCd::Constants;
use IRCd::Channel::Topic;
use IRCd::Modes::Channel::Ban;
use IRCd::Modes::Channel::Limit;
use IRCd::Modes::Channel::Moderated;
use IRCd::Modes::Channel::NoExternal;
use IRCd::Modes::Channel::Op;
use IRCd::Modes::Channel::Oper;
use IRCd::Modes::Channel::Topic;
use IRCd::Modes::Channel::Voice;

package IRCd::Channel;

sub new {
    my $class = shift;
    my $self  = {
        'name'      => shift,
        'clients'   => {},
        'modes'     => {},
        'privilege' => {},
        'topic'     => undef,
    };
    bless $self, $class;

    # TODO: iterate over all possible modes
    $self->{modes}->{b} = IRCd::Modes::Channel::Ban->new($self);
    $self->{modes}->{l} = IRCd::Modes::Channel::Limit->new($self);
    $self->{modes}->{m} = IRCd::Modes::Channel::Moderated->new($self);
    $self->{modes}->{n} = IRCd::Modes::Channel::NoExternal->new($self);
    $self->{modes}->{o} = IRCd::Modes::Channel::Op->new($self);
    $self->{modes}->{O} = IRCd::Modes::Channel::Oper->new($self);
    $self->{modes}->{t} = IRCd::Modes::Channel::Topic->new($self);
    $self->{modes}->{v} = IRCd::Modes::Channel::Voice->new($self);
    foreach(keys($self->{modes}->%*)) {
        my $level  = $self->{modes}->{$_}->level();
        my $symbol = $self->{modes}->{$_}->symbol();
        $self->{privilege}->{$level} = $self->{modes}->{$_}->symbol() if($level ne "" and $symbol ne "");
    }
    $self->{topic} = IRCd::Channel::Topic->new("", $self);

    return $self;
}

# This needs to be done after the client has been added, otherwise modes might not set properly
sub initModes {
    # used for modes
    my $self   = shift;
    my $client = shift;
    my $ircd   = shift;

    # Set initial modes
    foreach my $chanModes (values($ircd->{config}->{channelmodes}->%*)) {
        foreach(keys($chanModes->%*)) {
            my $name  = $_;
            my $param = $chanModes->{$name}->{param};
            if(ref($param) eq 'HASH') {
                $param = "";
            }
            # we need to pass the client, otherwise the mode setting won't have a user to ref to
            $self->{modes}->{$name}->grant($client,  "+", $name, $param // undef, 1, 0);
        }
    }
}

sub addClient {
    my $self     = shift;
    my $client   = shift;
    my $ircd     = $client->{ircd};
    my $mask     = $client->getMask(1);

    return if($self->resides($client));
    my $limit = $self->{modes}->{l}->get();
    if($self->size() >= $limit and $limit > 0) {
        # Channel is full
        # XXX: Does Pidgin recognise this?
        $client->{log}->info("[$self->{name}] Channel is full");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANNELISFULL  . " $client->{nick} $self->{name} :Cannot join channel (+l)");
        return;
    }
    if($self->{modes}->{b}->has($client)) {
        $client->{log}->info("[$self->{name}] User (nick: $client->{nick}) is banned from the channel");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_BANNEDFROMCHAN . " $client->{nick} $self->{name} :Cannot join channel (+b)");
        return;
    }
    if($self->{modes}->{O}->get() and !$client->{modes}->{o}->has($client)) {
        $client->{log}->info("[$self->{name}] User (nick: $client->{nick}) attempted to join oper-only (+O) channel $self->{name}");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_OPERONLY . " $client->{nick} $self->{name} :Cannot join channel $self->{name} (IRCops only)");
        return;
    }
    $self->{clients}->{lc($client->{nick})} = $client;
    $self->sendToRoom($client, ":$mask JOIN :$self->{name}");
    if($self->size() == 1) {
        # Grant the founding user op
        $self->{modes}->{o}->grant($client, "+", "o", $client->{nick}, 1, 0);
    }
    $client->{log}->info("[$self->{name}] Added client (nick: $client->{nick}) to channel");

    # TODO: Default modes?
    my $userModes = "";
    foreach(values($self->{clients}->%*)) {
        my $userSymbol = $self->{privilege}->{$self->getStatus($_)} // "";
        $client->write(":$ircd->{host} "  . IRCd::Constants::RPL_NAMREPLY      . " $client->{nick} = $self->{name} :$userSymbol$_->{nick}");
    }
    $client->write(":$ircd->{host} "  . IRCd::Constants::RPL_ENDOFNAMES    . " $client->{nick} $self->{name} :End of /NAMES list.");
    $client->write(":$ircd->{host} "  . IRCd::Constants::RPL_TOPIC         . " $client->{nick} $self->{name} :" . $self->{topic}->get() . "\r\n") if($self->{topic}->get() ne "");

    my $modes = $self->getModeStrings("+");
    if($modes->{args}) {
        $client->write(":$ircd->{host} MODE $self->{name} $modes->{characters} $modes->{args}");
    } else {
        $client->write(":$ircd->{host} MODE $self->{name} $modes->{characters}");
    }
}
sub quit {
    my $self   = shift;
    my $client = shift;
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask(1);
    my $msg    = shift // "Leaving.";
    if($self->{clients}->{lc($client->{nick})} // "") {
        # We should be in the room b/c of the caller but let's be safe.
        $client->{log}->info("[$self->{name}] Removed (QUIT) a client (nick: $client->{nick}) from channel");
        $self->stripModes($client, 0);
        $self->sendToRoom($client, ":$mask QUIT :$msg", 0, 1);
        delete $self->{clients}->{lc($client->{nick})};
        return;
    }

}
sub part {
    my $self   = shift;
    my $client = shift;
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask(1);
    my $msg    = shift;
    my $forCloak = shift // 0;
    if($self->{clients}->{lc($client->{nick})}) {
        $client->{log}->info("[$self->{name}] Removed (PART) a client (nick: $client->{nick}) from channel");
        $self->sendToRoom($client, ":$mask PART $self->{name} :$msg", 1, 1);
        $self->stripModes($client, 0) if(!$forCloak);
        delete $self->{clients}->{lc($client->{nick})};
    } else {
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{name} :You're not on that channel");
    }
    my $chanSize = keys($self->{clients}->%*);
    if($chanSize == 0 and !$forCloak) {
        # Don't destroy the room if we're leaving for a 'changing host' message
        # It'll result in a crash because of the ->addClient on a dead Channel object
        $client->{log}->info("[$self->{name}] Deleting the room");
        delete $ircd->{channels}->{$self->{name}};
    }
}

sub kick {
    my $self         = shift;
    my $client       = shift;
    my $ircd         = $client->{ircd};
    my $mask         = $client->getMask(1);
    my $targetUser   = shift;
    my $targetClient = shift;
    my $kickReason   = shift // "Kicked.";

    if(!$self->{clients}->{lc($client->{nick})}) {
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{name} :You're not on that channel");
        return;
    }
    if($self->getStatus($client) >= 3) {
        if(($targetClient = $self->{clients}->{lc($targetUser)})) {
            $self->stripModes($targetClient, 0);
            $self->sendToRoom($client, ":$mask KICK $self->{name} $targetUser :$kickReason");
            delete $self->{clients}->{lc($targetUser)};
        } else {
            $client->write(":$ircd->{host} " . IRCd::Constants::ERR_USERNOTINCHANNEL . " $client->{nick} $self->{name} :They aren't on that channel");
            return;
        }
    } else {
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANOPRIVSNEEDED . " $client->{nick} $self->{name} :You must be a channel operator");
        return;
    }
}

sub topic {
    my $self   = shift;
    my $client = shift;
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask(1);
    my $topic  = shift;
    my $force  = shift // 0;

    if(!$self->{clients}->{lc($client->{nick})}) {
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{name} :You're not on that channel");
        return;
    }
    # XXX: +t/-t
    # XXX: RPL_NOTOPIC is a thing too
    # XXX: I think we may need to tell the clients differently?
    if($topic eq "") {
        my $topicText = $self->{topic}->get();
        my $topicMask = $self->{topic}->metadata()->{who};
        my $topicTime = $self->{topic}->metadata()->{time};
        if($topicText ne "") {
            $client->write(":$ircd->{host} " . IRCd::Constants::RPL_TOPIC        . " $client->{nick} $self->{name} :$topicText");
            $client->write(":$ircd->{host} " . IRCd::Constants::RPL_TOPICWHOTIME . " $client->{nick} $self->{name} $topicMask $topicTime");
        } else {
            $client->write(":$ircd->{host} " . IRCd::Constants::RPL_NOTOPIC      . " $client->{nick} $self->{name} :No topic is set");
        }
    } else {
        if($force == 0 && $self->{modes}->{t}->get()) {
            if($self->getStatus($client) < 3) {
                $client->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANOPRIVSNEEDED . " $client->{nick} $self->{name} :You must be a channel operator");
                return;
            }
        }
        $self->{topic}->set($client, $topic, $force, 1);
    }
}

###                 ###
### Mode operations ###
###                 ###
sub getStatus {
    my $self   = shift;
    my $client = shift;
    my $mask   = $client->getMask(1);

    my $highestLevel = 0;
    foreach(keys($self->{modes}->%*)) {
        if(my $rank = $self->{modes}->{$_}->level()) {
            $highestLevel = $rank if($self->{modes}->{$_}->has($client) and $rank > $highestLevel);
        }
    }
    return $highestLevel;
}
sub stripModes {
    my $self     = shift;
    my $client   = shift;
    my $announce = shift // 0;
    foreach(keys($self->{modes}->%*)) {
        $self->{modes}->{$_}->revoke($client, undef, undef, undef, 1, $announce) if($self->{modes}->{$_}->has($client));
    }
}
sub getModeStrings {
    my $self        = shift;
    my $characters  = shift // "+";
    my $modes       = "";
    my $args        = "";
    foreach(keys($self->{modes}->%*)) {
        my $chanwide  = $self->{modes}->{$_}->{chanwide};
        if($chanwide) {
            my $provides = $self->{modes}->{$_}->{provides};
            my $value    = $self->{modes}->{$_}->get();
            if($value > 0 and $value ne '') {
                $characters .= $provides;
                if($self->{modes}->{$_}->{hasparam}) {
                    $args       .= $value . " ";
                }
            }
        }
    }
    return {
        'characters' => $characters,
        'args'       => $args,
    };
}

###        ###
###  Misc  ###
###        ###
sub size {
    my $self = shift;
    return keys($self->{clients}->%*);
}
sub resides {
    my $self   = shift;
    my $client = shift;
    my $mask   = $client->getMask(1);
    my $msg    = shift;
    return 1 if ($self->{clients}->{lc($client->{nick})});
    return 0;
}
sub sendToRoom {
    my $self   = shift;
    my $client = shift // undef;
    my $ircd;
    if($client) {
        $ircd  = $client->{ircd};
    } else {
        $ircd = $self->{ircd};
    }
    my $msg    = shift;
    my $sendToSelf = shift // 1;
    # $force is needed for banned QUITs/PARTs, etc
    # TODO: Create a ->privmsg and ->notice for IRCd::Channel, alleviating the need for
    # sendToRoom to handle so many of these cases
    my $force  = shift // 0;
    if($client) {
        if($self->{modes}->{b}->has($client) and $self->getStatus($client) < $self->{modes}->{o}->level()) {
            $client->{log}->info("[$self->{name}] User (nick: $client->{nick}) is banned from the channel $self->{name}");
            $client->write(":$ircd->{host} " . IRCd::Constants::ERR_CANNOTSENDTOCHAN . " $client->{nick} $self->{name} :Cannot send to channel (you're banned)");
            return;
        }
        if($msg =~ /(PRIVMSG|NOTICE)/ and $self->{modes}->{m}->get() and $self->getStatus($client) < $self->{modes}->{v}->level()) {
            $client->{log}->info("[$self->{name}] User (nick: $client->{nick} tried to speak on muted channel $self->{name})");
            $client->write(":$ircd->{host} " . IRCd::Constants::ERR_CANNOTSENDTOCHAN . " $client->{nick} $self->{name} :Cannot send to channel (+m)");
            return;
        }
        if($self->{modes}->{n}->get() and !$self->{clients}->{lc($client->{nick})}) {
            $client->{log}->info("[$self->{name}] User (nick: $client->{nick}) tried to externally message $self->{name}");
            $client->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::ERR_CANNOTSENDTOCHAN . " $client->{nick} $self->{name} :Cannot send to channel (no external messages)\r\n");
            return;
        }
    }
    foreach(values($self->{clients}->%*)) {
        next if(($_ eq $client) and !$sendToSelf);
        if($msg =~ /\r\n/) {
            # TODO: carp
            warn caller . " is misbehaving and sending a newline!";
            $msg =~ s/\r\n//;
        }
        $_->{socket}->{sock}->write($msg . "\r\n");
    }
}

1;
