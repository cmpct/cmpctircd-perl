#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;

package IRCd::Modes::Channel::Limit;

sub new {
    my $class = shift;
    my $self  = {
        'name'     => 'limit',
        'provides' => 'l',
        'desc'     => 'Provides the +l (limit) mode for limiting the maximum amount of users in a channel.',
        'affects'  => {},
        'channel'  => shift,

        'limit'    => 0,
        # Can it be set on a user, or just a channel at large?
        'chanwide' => 1,
        'hasparam' => 1,
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
    my $mode     = shift // "l";
    my $args     = shift // $self->{limit};
    my $force    = shift // 0;
    my $announce = shift // 1;

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
    # TODO: Only one arg of type integer
    my $mask = $client->getMask(1);
    if($self->{limit} eq $args) {
        # Is the same as before, ignore.
        return 0;
    } else {
        $self->{limit} = $args;
    }
    $self->{channel}->sendToRoom($client, ":$mask MODE $self->{channel}->{name} $modifier$mode $args") if($announce);
    return 1;
}
sub revoke {
    my $self     = shift;
    my $client   = shift;
    my $config   = $client->{config};
    my $ircd     = $client->{ircd};
    my $modifier = shift // "-";
    my $mode     = shift // "l";
    my $args     = shift // $self->{limit};
    my $force    = shift // 0;
    my $announce = shift // 1;

    # TODO: No arg required
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
    # TODO: Should we check that their arg matches the current mode?
    # I don't think so.
    $self->{limit} = 0;
    $self->{channel}->sendToRoom($client, ":$mask MODE $self->{channel}->{name} $modifier$mode $args") if($announce);
    return 1;
}

sub get {
    my $self = shift;
    return $self->{limit};
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
