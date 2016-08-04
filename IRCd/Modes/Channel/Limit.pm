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

        'limit'    => 50,
    };
    bless $self, $class;
    return $self;
}

# XXX: Limit is different because it doesn't affect clients per-se.

sub grant {
    my $self     = shift;
    my $client   = shift;
    my $modifier = shift // "+";
    my $mode     = shift // "l";
    my $args     = shift // $self->{limit};
    my $force    = shift // 0;

    if(!$self->{channel}->{clients}->{$client->{nick}}) {
        print "They're not in the room!\r\n";
        $client->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{name} :You're not on that channel\r\n");
        return;
    }
    if(!$force and $self->{channel}->getStatus($client) < $self->level()) {
        print "No permission!\r\n";
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANOPRIVSNEEDED . " $client->{nick} $self->{name} :You must be a channel operator\r\n");
        return;
    }
    # TODO: Only one arg of type integer
    my $mask = $client->getMask();
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
    my $modifier = shift // "-";
    my $mode     = shift // "l";
    my $args     = shift // $self->{limit};
    my $force    = shift // 0;

    # TODO: No arg required
    if(!$self->{channel}->{clients}->{$client->{nick}}) {
        print "They're not in the room!\r\n";
        $client->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{name} :You're not on that channel\r\n");
        return;
    }
    if(!$force and $self->{channel}->getStatus($client) < $self->level()) {
        print "No permission!\r\n";
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANOPRIVSNEEDED . " $client->{nick} $self->{name} :You must be a channel operator\r\n");
        return;
    }
    my $mask = $client->getMask();
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
