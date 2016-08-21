#!/usr/bin/perl
use strict;
use warnings;
no warnings "experimental::postderef"; # for older perls (<5.24)
use feature 'postderef';

use IRCd::Cloak;
use IRCd::Constants;

package IRCd::Modes::User::Cloak;

sub new {
    my $class = shift;
    my $self  = {
        'name'     => 'cloak',
        'provides' => 'x',
        'desc'     => 'Provides the +x (cloak) for protecting a user\'s IP.',
        'affects'  => {},
        'client'   => shift,

        'hasparam' => 0,
    };
    bless $self, $class;
    return $self;
}

sub grant {
    my $self     = shift;
    my $client   = $self->{client};
    my $socket   = $client->{socket}->{sock};
    my $config   = $client->{config};
    my $ircd     = $client->{ircd};
    my $modifier = shift // "+";
    my $mode     = shift // "x";
    my $args     = shift // $client->{nick};
    my $force    = shift // 0;
    my $announce = shift // 1;
    my $targetClient = undef;
    my $mask = $client->getMask(1);

    return if($self->{affects}->{$client});
    # Generate a cloak
    # if the IP matches the host, then use IP cloaking, otherwise fall back to DNS
    if ($client->{ip} eq $client->{host}) {
        # detect v6, otherwise fall back to v4
        if (index($client->{ip}, ":") != -1) {
            $client->{cloak} = IRCd::Cloak::unreal_cloak_v6($client->{ip}, $ircd->{cloak_keys}[0], $ircd->{cloak_keys}[1], $ircd->{cloak_keys}[2]);
        } else {
            $client->{cloak} = IRCd::Cloak::unreal_cloak_v4($client->{ip}, $ircd->{cloak_keys}[0], $ircd->{cloak_keys}[1], $ircd->{cloak_keys}[2]);
        }
    } else {
        # The DNS version of the function needs hidden_host as well
        # XXX: should this be ircd->hidden_host?
        $client->{cloak} = IRCd::Cloak::unreal_cloak_dns($client->{host}, $config->{hidden_host}, $ircd->{cloak_keys}[0], $ircd->{cloak_keys}[1], $ircd->{cloak_keys}[2]);
    }

    $self->{client}->{log}->debug("[$client->{nick}] setting +x");
    
    $self->{client}->write(":$ircd->{host} " . IRCd::Constants::RPL_HOSTHIDDEN . " $client->{nick} $client->{cloak} :is now your displayed host\r\n");
    $self->{client}->write(":$mask MODE $client->{nick} $modifier$mode $args") if $announce;
    $self->{affects}->{$client} = 1;

    # Rejoin all of our channels
    foreach my $chan (keys($ircd->{channels}->%*)) {
        $ircd->{channels}->{$chan}->part($client, "Changing host", 1);
        $ircd->{channels}->{$chan}->addClient($client);
    }
}
sub revoke {
    my $self     = shift;
    my $client   = $self->{client};
    my $socket   = $client->{socket}->{sock};
    my $config   = $client->{config};
    my $ircd     = $client->{ircd};
    my $modifier = shift // "-";
    my $mode     = shift // "x";
    my $args     = shift // $client->{nick};
    my $force    = shift // 0;
    my $announce = shift // 1;
    my $targetClient = undef;

    return if(!$self->{affects}->{$client});
    my $mask = $client->getMask(0);
    $self->{client}->{log}->debug("[$client->{nick}] unsetting +x");
    $client->{cloak} = $client->{host};
    $self->{client}->write(":$ircd->{host} " . IRCd::Constants::RPL_HOSTHIDDEN . " $client->{nick} $client->{host} :is now your displayed host\r\n");
    $self->{client}->write(":$mask MODE $client->{nick} $modifier$mode $args") if $announce;
    delete $self->{affects}->{$client};

    # Rejoin all of our channels
    foreach my $chan (keys($ircd->{channels}->%*)) {
        $ircd->{channels}->{$chan}->part($client, "Changing host", 1);
        $ircd->{channels}->{$chan}->addClient($client);
    }
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
    return 0;
}
sub symbol {
    return 'N/A';
}

1;
