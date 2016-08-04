#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
use IRCd::Constants;

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
        # topic
    };
    bless $self, $class;
    $self->{modes}->{o} = IRCd::Modes::Channel::Op->new($self);
    $self->{modes}->{l} = IRCd::Modes::Channel::Limit->new($self);
    foreach(keys($self->{modes}->%*)) {
        my $level  = $self->{modes}->{$_}->level();
        my $symbol = $self->{modes}->{$_}->symbol();
        $self->{privilege}->{$level} = $self->{modes}->{$_}->symbol() if($level ne "" and $symbol ne "");
    }
    return $self;
}

sub setMode {
    my $self  = shift;
    my $modes = shift;
    # Check how valid the modes are
    # Another issue is keys.. and other params
    push @{$self->{modes}}, $modes;
}
sub addClient {
    my $self     = shift;
    my $client   = shift;
    my $ircd     = $client->{ircd};
    my $mask     = $client->getMask();
    my $modes    = "";
    my $chanSize = keys($self->{clients}->%*);

    return if($self->resides($client));
    if($chanSize >= $self->{modes}->{l}->get()) {
        # Channel is full
        # XXX: Does Pidgin recognise this?
        print "Channel is full\r\n";
        $client->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANNELISFULL . " $client->{nick} $self->{name} :Cannot join channel (+l)\r\n");
        return;
    }
    $self->{clients}->{$client->{nick}} = $client;
    $self->sendToRoom($client, ":$mask JOIN :$self->{name}");
    my $chanSize = keys($self->{clients}->%*);
    if($chanSize == 1) {
        # Grant the founding user op
        $self->{modes}->{o}->grant($client, "+", "o", $client->{nick}, 1);
    }
    print "Added client to channel $self->{name}\r\n";

    # TODO: Default modes?
    my $userModes = "";
    foreach(values($self->{clients}->%*)) {
        my $userSymbol = $self->{privilege}->{$self->getStatus($_)};
        $client->{socket}->{sock}->write(":$ircd->{host} "  . IRCd::Constants::RPL_NAMREPLY      . " $client->{nick} \@ $self->{name} :$userSymbol$_->{nick}\r\n");
    }
    $client->{socket}->{sock}->write(":$ircd->{host} "  . IRCd::Constants::RPL_ENDOFNAMES    . " $client->{nick} $self->{name} :End of /NAMES list.\r\n");
    $client->{socket}->{sock}->write(":$ircd->{host} "  . IRCd::Constants::RPL_TOPIC         . " $client->{nick} $self->{name} :This is a topic.\r\n");
    $client->{socket}->{sock}->write(":$ircd->{host} "  . IRCd::Constants::RPL_CHANNELMODEIS . " $client->{nick} $self->{name} +$modes\r\n");
    #$client->{socket}->{sock}->write(":$ircd->{host} "  . IRCd::Constants::RPL_CREATIONTIME  . " $client->{nick} $self->{name} " . time() . "\r\n");
}
sub quit {
    my $self   = shift;
    my $client = shift;
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();
    my $msg    = shift // "Leaving.";
    if($self->{clients}->{$client->{nick}}) {
        # We should be in the room b/c of the caller but let's be safe.
        print "Removed (QUIT) a client from channel $self->{name}\r\n";
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
        print "Removed (PART) a client from channel $self->{name}\r\n";
        $self->sendToRoom($client, ":$mask PART $self->{name} :$msg");
        $self->stripModes($client, 0);
        delete $self->{clients}->{$client->{nick}};
    }
    my $chanSize = keys($self->{clients}->%*);
    if($chanSize == 0) {
        print "Deleting the room\r\n";
        delete $ircd->{channels}->{$self->{name}};
    }
    return;
    # If we get here, they weren't in the room.
    # XXX: Is this right?
    $client->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{name} :You're not on that channel\r\n");
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
            warn caller . " is misbehaving and sending a newline!";
            $msg =~ s/\r\n//;
        }
        $_->{socket}->{sock}->write($msg . "\r\n");
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

1;
