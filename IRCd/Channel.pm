#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
use IRCd::Constants;

use IRCd::Channel::Topic;
use IRCd::Modes::Channel::Op;
use IRCd::Modes::Channel::Limit;

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
    $self->{modes}->{o} = IRCd::Modes::Channel::Op->new($self);
    $self->{modes}->{l} = IRCd::Modes::Channel::Limit->new($self);
    foreach(keys($self->{modes}->%*)) {
        my $level  = $self->{modes}->{$_}->level();
        my $symbol = $self->{modes}->{$_}->symbol();
        $self->{privilege}->{$level} = $self->{modes}->{$_}->symbol() if($level ne "" and $symbol ne "");
    }
    $self->{topic} = IRCd::Channel::Topic->new("", $self);
    return $self;
}

sub addClient {
    my $self     = shift;
    my $client   = shift;
    my $ircd     = $client->{ircd};
    my $mask     = $client->getMask();

    return if($self->resides($client));
    if($self->size() >= $self->{modes}->{l}->get()) {
        # Channel is full
        # XXX: Does Pidgin recognise this?
        $client->{log}->info("[$self->{name}] Channel is full");
        $client->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANNELISFULL . " $client->{nick} $self->{name} :Cannot join channel (+l)\r\n");
        return;
    }
    $self->{clients}->{$client->{nick}} = $client;
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
        $client->{socket}->{sock}->write(":$ircd->{host} "  . IRCd::Constants::RPL_NAMREPLY      . " $client->{nick} \@ $self->{name} :$userSymbol$_->{nick}\r\n");
    }
    $client->{socket}->{sock}->write(":$ircd->{host} "  . IRCd::Constants::RPL_ENDOFNAMES    . " $client->{nick} $self->{name} :End of /NAMES list.\r\n");
    $client->{socket}->{sock}->write(":$ircd->{host} "  . IRCd::Constants::RPL_TOPIC         . " $client->{nick} $self->{name} :" . $self->{topic}->get() . "\r\n") if($self->{topic}->get() ne "");
    # XXX: Need a way of knowing if MODEs are MODEable (on join)

    my $modes       = "";
    my $characters  = "+";
    my $args        = "";
    my $provides    = "";
    my $value       = "";
    # XXX: Port this to a function so we can do /MODE #chan
    foreach(keys($self->{modes}->%*)) {
        my $chanwide  = $self->{modes}->{$_}->{chanwide};
        if($chanwide) {
            $provides = $self->{modes}->{$_}->{provides};
            $value    = $self->{modes}->{$_}->get();
            $characters .= $provides;
            $args       .= $value . " ";
        }
    }
    $client->{log}->debug("[$self->{name}] Writing: $characters $args");
    $client->{socket}->{sock}->write(":$ircd->{host} "  . IRCd::Constants::RPL_CHANNELMODEIS . " $client->{nick} $self->{name} $characters $args\r\n");
    #$client->{socket}->{sock}->write(":$ircd->{host} "  . IRCd::Constants::RPL_CREATIONTIME  . " $client->{nick} $self->{name} " . time() . "\r\n");
}
sub quit {
    my $self   = shift;
    my $client = shift;
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();
    my $msg    = shift // "Leaving.";
    if($self->{clients}->{$client->{nick}} // "") {
        # We should be in the room b/c of the caller but let's be safe.
        $client->{log}->info("[$self->{name}] Removed (QUIT) a client (nick: $client->{name}) from channel");
        $self->stripModes($client, 0);
        $self->sendToRoom($client, ":$mask QUIT :$msg");
        delete $self->{clients}->{$client->{nick}};
        return;
    }

}
sub part {
    my $self   = shift;
    my $client = shift;
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();
    my $msg    = shift;
    if($self->{clients}->{$client->{nick}}) {
        $client->{log}->info("[$self->{name}] Removed (PART) a client (nick: $client->{name}) from channel");
        $self->sendToRoom($client, ":$mask PART $self->{name} :$msg");
        $self->stripModes($client, 0);
        delete $self->{clients}->{$client->{nick}};
    } else {
        $client->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{name} :You're not on that channel\r\n");
    }
    my $chanSize = keys($self->{clients}->%*);
    if($chanSize == 0) {
        $client->{log}->info("[$self->{name}] Deleting the room");
        delete $ircd->{channels}->{$self->{name}};
    }
    # If we get here, they weren't in the room.
}

sub kick {
    my $self         = shift;
    my $client       = shift;
    my $ircd         = $client->{ircd};
    my $mask         = $client->getMask();
    my $targetUser   = shift;
    my $targetClient = shift;
    my $kickReason   = shift;

    if(!$self->{clients}->{$client->{nick}}) {
        $client->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{name} :You're not on that channel\r\n");
        return;
    }
    if($self->getStatus($client) >= 3) {
        if(($targetClient = $self->{clients}->{$targetUser})) {
            $self->stripModes($targetClient, 0);
            $self->sendToRoom($client, ":$mask KICK $self->{name} $targetUser :$kickReason");
            delete $self->{clients}->{$targetUser};
        } else {
            $client->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::ERR_USERNOTINCHANNEL . " $client->{nick} $self->{name} :They aren't on that channel\r\n");
            return;
        }
    } else {
        $client->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANOPRIVSNEEDED . " $client->{nick} $self->{name} :You must be a channel operator\r\n");
        return;
    }
}

sub topic {
    my $self   = shift;
    my $client = shift;
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();
    my $topic  = shift;

    if(!$self->{clients}->{$client->{nick}}) {
        $client->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{name} :You're not on that channel\r\n");
        return;
    }
    if($self->getStatus($client) < 3) {
        $client->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANOPRIVSNEEDED . " $client->{nick} $self->{name} :You must be a channel operator\r\n");
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
            $client->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::RPL_TOPIC        . " $client->{nick} $self->{name} :$topicText\r\n");
            $client->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::RPL_TOPICWHOTIME . " $client->{nick} $self->{name} $topicMask $topicTime\r\n");
        } else {
            $client->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::RPL_NOTOPIC      . " $client->{nick} $self->{name} :No topic is set\r\n");
        }
    } else {
        $self->{topic}->set($client, $topic, 0, 1);
    }
}

###                 ###
### Mode operations ###
###                 ###
sub getStatus {
    my $self   = shift;
    my $client = shift;
    my $mask   = $client->getMask();

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
    my $mask   = $client->getMask();
    my $msg    = shift;

    return 1 if ($self->{clients}->{$client->{nick}});
    return 0;
}
sub sendToRoom {
    my $self   = shift;
    my $client = shift;
    my $msg    = shift;
    my $sendToSelf = shift // 1;

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
