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
    my $mode     = shift // "o";
    my $args     = shift // $client->{nick};
    my $force    = shift // 0;
    my $announce = shift // 1;
    my $targetClient = undef;

    if(!$self->{channel}->{clients}->{$client->{nick}}) {
        print "They're not in the room!\r\n";
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{name} :You're not on that channel\r\n");
        return;
    }
    my $targetNick = $args;
    # NOTE: Let's keep ERR_NOSUCHNICK here rather than ERR_USERNOTONCHANNEL to avoid +i leaks
    # There's only a semantic difference between the two (see: revoke).
    if(!($targetClient = $self->{channel}->{clients}->{$targetNick})) {
        print "The target doesn't exist!\r\n";
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHNICK . " $client->{nick} $targetNick :No such nick/channel\r\n");
        return;
    }
    if(!$force and $self->{channel}->getStatus($client) < $self->level()) {
        print "No permission!\r\n";
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANOPRIVSNEEDED . " $client->{nick} $self->{name} :You must be a channel operator\r\n");
        return;
    }
    my $mask = $client->getMask();
    $self->{channel}->sendToRoom($client, ":$mask MODE $self->{channel}->{name} $modifier$mode $args") if $announce;
    $self->{affects}->{$targetClient} = 1;
}
sub revoke {
    my $self     = shift;
    my $client   = shift;
    my $socket   = $client->{socket}->{sock};
    my $config   = $client->{config};
    my $ircd     = $client->{ircd};
    my $modifier = shift // "-";
    my $mode     = shift // "o";
    my $args     = shift // $client->{nick};
    my $force    = shift // 0;
    my $announce = shift // 1;
    my $targetClient = undef;

    if(!$self->{channel}->{clients}->{$client->{nick}}) {
        print "They're not in the room!\r\n";
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $client->{nick} $self->{name} :You're not on that channel\r\n");
        return;
    }
    my $targetNick = $args;
    # NOTE: Let's keep ERR_NOSUCHNICK here rather than ERR_USERNOTONCHANNEL to avoid +i leaks
    # There's only a semantic difference between the two (see: grant)
    if(!($targetClient = $self->{channel}->{clients}->{$targetNick})) {
        print "The target doesn't exist!\r\n";
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_NOSUCHNICK . " $client->{nick} $targetNick :No such nick/channel\r\n");
        return;
    }
    # TODO: Consider the privilege of the person we're affecting?
    if(!$force and $self->{channel}->getStatus($client) < $self->level()) {
        print "No permission!\r\n";
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANOPRIVSNEEDED . " $client->{nick} $self->{name} :You must be a channel operator\r\n");
        return;
    }
    my $mask = $client->getMask();
    $self->{channel}->sendToRoom($client, ":$mask MODE $self->{channel}->{name} $modifier$mode $args") if $announce;
    delete $self->{affects}->{$targetClient};
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
