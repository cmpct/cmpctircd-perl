#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;

package IRCd::Modes::Channel::Op;

sub new {
    my $class = shift;
    my $self  = {
        'name'     => 'op',
        'provides' => 'o',
        'desc'     => 'Provides the +o (op) mode for moderating a channel.',
        'affects'  => {},
        'channel'  => shift,

        'chanwide' => 0,
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
    my $mode     = shift // "o";
    my $args     = shift // $client->{nick};
    my $force    = shift // 0;
    my $announce = shift // 1;
    my $targetClient = undef;

    if(!$self->{channel}->{clients}->{$client->{nick}}) {
        $client->{log}->info("[$self->{channel}->{name}] Client (nick: $client->{nick}) not in the room!");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{channel}->{name} :You're not on that channel");
        return 0;
    }
    my $targetNick = $args;
    # NOTE: Let's keep ERR_NOSUCHNICK here rather than ERR_USERNOTONCHANNEL to avoid +i leaks
    # There's only a semantic difference between the two (see: revoke).
    if(!($targetClient = $self->{channel}->{clients}->{$targetNick})) {
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHNICK . " $client->{nick} $targetNick :No such nick/channel");
        return 0;
    }
    if(!$force and $self->{channel}->getStatus($client) < $self->level()) {
        $client->{log}->info("[$self->{channel}->{name}] No permission for client (nick: $client->{nick})!");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANOPRIVSNEEDED . " $client->{nick} $self->{channel}->{name} :You must be a channel operator");
        return 0;
    }
    my $mask = $client->getMask(1);
    $self->{channel}->sendToRoom($client, ":$mask MODE $self->{channel}->{name} $modifier$mode $args") if $announce;
    $self->{affects}->{$targetClient} = 1;
    return 1;
}
sub revoke {
    my $self     = shift;
    my $client   = shift;
    my $config   = $client->{config};
    my $ircd     = $client->{ircd};
    my $modifier = shift // "-";
    my $mode     = shift // "o";
    my $args     = shift // $client->{nick};
    my $force    = shift // 0;
    my $announce = shift // 1;
    my $targetClient = undef;

    if(!$self->{channel}->{clients}->{$client->{nick}}) {
        $client->{log}->info("[$self->{channel}->{name}] Client (nick: $client->{nick}) not in the room!");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{channel} :You're not on that channel");
        return 0;
    }
    my $targetNick = $args;
    # NOTE: Let's keep ERR_NOSUCHNICK here rather than ERR_USERNOTONCHANNEL to avoid +i leaks
    # There's only a semantic difference between the two (see: grant)
    if(!($targetClient = $self->{channel}->{clients}->{$targetNick})) {
        $client->{log}->info("[$self->{channel}->{name}] Target (nick: $targetNick) not in the room!");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHNICK . " $client->{nick} $targetNick :No such nick/channel");
        return 0;
    }
    # TODO: Consider the privilege of the person we're affecting?
    if(!$force and $self->{channel}->getStatus($client) < $self->level()) {
        $client->{log}->info("[$self->{channel}->{name}] No permission for client (nick: $client->{nick})!");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANOPRIVSNEEDED . " $client->{nick} $self->{channel}->{name} :You must be a channel operator");
        return 0;
    }
    my $mask = $client->getMask(1);
    $self->{channel}->sendToRoom($client, ":$mask MODE $self->{channel}->{name} $modifier$mode $args") if $announce;
    delete $self->{affects}->{$targetClient};
    return 1;
}
sub has {
    my $self   = shift;
    my $client = shift;
    return 1 if($self->{affects}->{$client});
    return 0;
}

sub level {
    # 0 => normal
    # 1 => voice
    # 2 => halfop
    # 3 => op
    # 4 => admin
    # 5 => owner
    return 3;
}
sub symbol {
    return '@';
}

1;
