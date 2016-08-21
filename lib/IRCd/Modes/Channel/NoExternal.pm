#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;

package IRCd::Modes::Channel::NoExternal;

sub new {
    my $class = shift;
    my $self  = {
        'name'     => 'noexternal',
        'provides' => 'n',
        'desc'     => 'Provides the +n (no external messages) mode.',
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
    my $socket   = $client->{socket}->{sock};
    my $config   = $client->{config};
    my $ircd     = $client->{ircd};
    my $modifier = shift // "+";
    my $mode     = shift // "n";
    my $args     = shift // "";
    my $force    = shift // 0;

    return if($self->{set});
    if(!$force and !$self->{channel}->{clients}->{$client->{nick}}) {
        $client->{log}->info("[$self->{channel}] Client (nick: $client->{nick}) not in the room!");
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{channel} :You're not on that channel\r\n");
        return;
    }
    if(!$force and $self->{channel}->getStatus($client) < $self->level()) {
        $client->{log}->info("[$self->{channel}] No permission for client (nick: $client->{nick})!");
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANOPRIVSNEEDED . " $client->{nick} $self->{channel} :You must be a channel operator\r\n");
        return;
    }
    my $mask = $client->getMask(1);
    $self->{channel}->sendToRoom($client, ":$mask MODE $self->{channel}->{name} $modifier$mode $args");
    $self->{set} = 1;
}
sub revoke {
    my $self     = shift;
    my $client   = shift;
    my $socket   = $client->{socket}->{sock};
    my $config   = $client->{config};
    my $ircd     = $client->{ircd};
    my $modifier = shift // "-";
    my $mode     = shift // "n";
    my $args     = shift // "";
    my $force    = shift // 0;

    return if(!$self->{set});
    if(!$self->{channel}->{clients}->{$client->{nick}}) {
        $client->{log}->info("[$self->{channel}] Client (nick: $client->{nick}) not in the room!");
        $client->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{channel} :You're not on that channel\r\n");
        return;
    }
    if(!$force and $self->{channel}->getStatus($client) < $self->level()) {
        $client->{log}->info("[$self->{channel}] No permission for client (nick: $client->{nick})!");
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANOPRIVSNEEDED . " $client->{nick} $self->{name} :You must be a channel operator\r\n");
        return;
    }
    my $mask = $client->getMask(1);
    $self->{set} = 0;
    $self->{channel}->sendToRoom($client, ":$mask MODE $self->{channel}->{name} $modifier$mode $args");
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
