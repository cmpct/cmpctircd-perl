#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;

package IRCd::Modes::Channel::Moderated;

sub new {
    my $class = shift;
    my $self  = {
        'name'     => 'moderated',
        'provides' => 'm',
        'desc'     => 'Provides the +m (moderated) mode.',
        'affects'  => {},
        'channel'  => shift,
        'set'      => 0,

        # Can it be set on a user, or just a channel at large?
        'chanwide' => 1,
        'hasparam' => 0,
    };
    bless $self, $class;
    return $self;
}

sub grant {
    my $self     = shift;
    my $client   = shift;
    my $config   = $client->{config};
    my $ircd     = $client->{ircd};
    my $modifier = shift // "+";
    my $mode     = shift // "v";
    my $args     = shift // "";
    my $force    = shift // 0;
    my $announce = shift // 1;

    return 0 if($self->{set});
    if(!$force and !$self->{channel}->{clients}->{$client->{nick}}) {
        $client->{log}->info("[$self->{channel}->{name}] Client (nick: $client->{nick}) not in the room!");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{channel} :You're not on that channel");
        return 0;
    }
    if(!$force and $self->{channel}->getStatus($client) < $self->level()) {
        $client->{log}->info("[$self->{channel}->{name}] No permission for client (nick: $client->{nick})!");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANOPRIVSNEEDED . " $client->{nick} $self->{channel} :You must be a channel operator");
        return 0;
    }
    my $mask = $client->getMask(1);
    $self->{channel}->sendToRoom($client, ":$mask MODE $self->{channel}->{name} $modifier$mode $args") if($announce);
    $self->{set} = 1;
    return 1;
}
sub revoke {
    my $self     = shift;
    my $client   = shift;
    my $config   = $client->{config};
    my $ircd     = $client->{ircd};
    my $modifier = shift // "-";
    my $mode     = shift // "v";
    my $args     = shift // "";
    my $force    = shift // 0;
    my $announce = shift // 1;

    return 0 if(!$self->{set});
    if(!$force and $self->{channel}->{clients}->{$client->{nick}}) {
        $client->{log}->info("[$self->{channel}->{name}] Client (nick: $client->{nick}) not in the room!");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{channel} :You're not on that channel");
        return 0;
    }
    if(!$force and $self->{channel}->getStatus($client) < $self->level()) {
        $client->{log}->info("[$self->{channel}->{name}] No permission for client (nick: $client->{nick})!");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANOPRIVSNEEDED . " $client->{nick} $self->{name} :You must be a channel operator");
        return 0;
    }
    my $mask = $client->getMask(1);
    $self->{set} = 0;
    $self->{channel}->sendToRoom($client, ":$mask MODE $self->{channel}->{name} $modifier$mode $args") if($announce);
    return 1;
}

sub get {
    my $self = shift;
    return $self->{set};
}

sub has {
    my $self   = shift;
    my $client = shift;
    return 1 if($self->{affects}->{$client});
    return 0;
}

sub level {
    my $self = shift;
    # Minimum to set is op.
    return IRCd::Modes::Channel::Op::level();
}
sub symbol {
    my $self = shift;
    return '';
}
1;
