#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;

package IRCd::Modes::Channel::Oper;

sub new {
    my $class = shift;
    my $self  = {
        'name'     => 'oper',
        'provides' => 'O',
        'desc'     => 'Provides the +O (oper-only) channel mode.',
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
    my $mode     = shift // "O";
    my $args     = shift // "";
    my $force    = shift // 0;
    my $announce = shift // 1;

    return if($self->{set});
    return if(!$client->{modes}->{o}->has($client));
    if(!$force and !$self->{channel}->{clients}->{$client->{nick}}) {
        $client->{log}->info("[$self->{channel}] Client (nick: $client->{nick}) not in the room!");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{channel} :You're not on that channel");
        return;
    }
    if(!$force and $self->{channel}->getStatus($client) < $self->level()) {
        $client->{log}->info("[$self->{channel}] No permission for client (nick: $client->{nick})!");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANOPRIVSNEEDED . " $client->{nick} $self->{channel} :You must be a channel operator");
        return;
    }
    my $mask = $client->getMask(1);
    $self->{channel}->sendToRoom($client, ":$mask MODE $self->{channel}->{name} $modifier$mode $args") if($announce);
    $self->{set} = 1;
}
sub revoke {
    my $self     = shift;
    my $client   = shift;
    my $config   = $client->{config};
    my $ircd     = $client->{ircd};
    my $modifier = shift // "-";
    my $mode     = shift // "O";
    my $args     = shift // "";
    my $force    = shift // 0;
    my $announce = shift // 1;

    return if(!$self->{set});
    return if(!$client->{modes}->{O}->has($client));
    if(!$self->{channel}->{clients}->{$client->{nick}}) {
        $client->{log}->info("[$self->{channel}] Client (nick: $client->{nick}) not in the room!");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{channel} :You're not on that channel");
        return;
    }
    if(!$force and $self->{channel}->getStatus($client) < $self->level()) {
        $client->{log}->info("[$self->{channel}] No permission for client (nick: $client->{nick})!");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANOPRIVSNEEDED . " $client->{nick} $self->{name} :You must be a channel operator");
        return;
    }
    my $mask = $client->getMask(1);
    $self->{set} = 0;
    $self->{channel}->sendToRoom($client, ":$mask MODE $self->{channel}->{name} $modifier$mode $args") if($announce);
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
