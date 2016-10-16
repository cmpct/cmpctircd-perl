#!/usr/bin/perl
use strict;
use warnings;

package IRCd::Modes::Channel::Permanent;

sub new {
    my $class = shift;
    my $self  = {
        'name'     => 'permanent',
        'provides' => 'P',
        'desc'     => 'Provides the +P (permanence) mode for preventing channel destruction when the last user leaves.',
        'affects'  => {},
        'channel'  => shift,

        # Can it be set on a user, or just a channel at large?
        'chanwide' => 1,
        'hasparam' => 0,
    };
    bless $self, $class;
    return $self;
}

# XXX: Need ircops for this, because this is an ircop-only MODE.
# XXX: (although we could make that configurable)

sub grant {
    my $self     = shift;
    my $client   = shift;
    my $config   = $client->{config};
    my $ircd     = $client->{ircd};
    my $modifier = shift // "+";
    my $mode     = shift // "P";
    my $args     = shift // $self->{limit};
    my $force    = shift // 0;

    if(!$self->{channel}->{clients}->{$client->{nick}}) {
        $client->{log}->info("[$self->{channel}] Client (nick: $client->{nick}) not in the room!");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{channel} :You're not on that channel");
        return;
    }
    if(!$force and $self->{channel}->getStatus($client) < $self->level()) {
        $client->{log}->info("[$self->{channel}] No permission for client (nick: $client->{nick})!");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANOPRIVSNEEDED . " $client->{nick} $self->{channel} :You must be a channel operator");
        return;
    }
    # TODO: Only one arg of type integer
    my $mask = $client->getMask(1);
    if($self->{limit} eq $args) {
        # Is the same as before, ignore.
        return;
    } else {
        $self->{limit} = $args;
    }
    $self->{channel}->sendToRoom($client, ":$mask MODE $self->{channel}->{name} $modifier$mode $args");
    #$self->{affects}->{$client} = 1;
}
sub revoke {
    my $self     = shift;
    my $client   = shift;
    my $config   = $client->{config};
    my $ircd     = $client->{ircd};
    my $modifier = shift // "-";
    my $mode     = shift // "P";
    my $args     = shift // $self->{limit};
    my $force    = shift // 0;

    # TODO: No arg required
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
    # TODO: Should we check that their arg matches the current mode?
    # I don't think so.
    $self->{limit} = 0;
    $self->{channel}->sendToRoom($client, ":$mask MODE $self->{channel}->{name} $modifier$mode $args");
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
