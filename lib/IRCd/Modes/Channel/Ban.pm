#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
no warnings "experimental::postderef"; # for older perls (<5.24)
use feature 'postderef';

use IRCd::Ban;
package IRCd::Modes::Channel::Ban;

sub new {
    my $class = shift;
    my $self  = {
        'name'     => 'ban',
        'provides' => 'b',
        'desc'     => 'Provides the +b (ban) mode for banning users from a channel.',
        'affects'  => {}, # maybe \&checkIfBanned?
        'bans'     => {},

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
    my $socket   = $client->{socket}->{sock};
    my $config   = $client->{config};
    my $ircd     = $client->{ircd};
    my $modifier = shift // "+";
    my $mode     = shift // "b";
    my $args     = shift // $client->{nick};
    my $force    = shift // 0;
    my $announce = shift // 1;
    my $targetClient = undef;

    if(!$force and $self->{channel}->getStatus($client) < $self->level()) {
        $client->{log}->info("[$self->{channel}] No permission for client (nick: $client->{nick})!");
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANOPRIVSNEEDED . " $client->{nick} $self->{channel} :You must be a channel operator\r\n");
        return 0;
    }
    my $mask = $client->getMask(1);
    my($nick, $user, $host) = ('*', '*', '*');
    # Infer characteristics of the ban based on the present characters
    # 'Fill in the blanks'
    if($args =~ /!/) {
        # Ban looks like '+b sam!sam@host'
        if($args =~ /@/) {
            my @splitHost = split('@', $args);
            my @splitNick = split('!', $splitHost[0]);
            $nick      = $splitNick[0];
            $user      = $splitNick[1];
        } else {
            # XXX: Check if '+b sam!sam' works
        }
    } elsif($args =~ /@/) {
        # Ban looks like '+b sam@host'
        my @splitUser = split('@', $args);
        $user      = $splitUser[0];
        $host      = $splitUser[1];
    } else {
        # Ban looks like '+b nick'
        $nick      = $args;
    }

    # $ban->getMask()?
    $client->{log}->debug("[$self->{channel}->{name}] $client->{nick} set a ban for $nick!$user\@$host");
    $self->{channel}->sendToRoom($client, ":$mask MODE $self->{channel}->{name} $modifier$mode $args") if $announce;
    my $ban = IRCd::Ban->new(
        'nick'   => $nick,
        'user'   => $user,
        'host'   => $host,
        'setter' => $client->{nick},
        'time'   => time(),
    );
    $self->{bans}->{$nick . '!' . $user . '@' . $host} = $ban;
    return 1;
}
sub revoke {
    my $self     = shift;
    my $client   = shift;
    my $socket   = $client->{socket}->{sock};
    my $config   = $client->{config};
    my $ircd     = $client->{ircd};
    my $modifier = shift // "-";
    my $mode     = shift // "b";
    my $args     = shift // $client->{nick};
    my $force    = shift // 0;
    my $announce = shift // 1;
    my $targetClient = undef;

    if(!$force and $self->{channel}->getStatus($client) < $self->level()) {
        $client->{log}->info("[$self->{channel}->{name}] No permission for client (nick: $client->{nick})!");
        $socket->write(":$ircd->{host} " . IRCd::Constants::ERR_CHANOPRIVSNEEDED . " $client->{nick} $self->{channel} :You must be a channel operator\r\n");
        return 0;
    }
    my($nick, $user, $host) = ('*', '*', '*');
    my $mask = $client->getMask(1);
    my $banMask = $args;
    if($self->{bans}->{$banMask}) {
        $client->{log}->debug("[$self->{channel}->{name}] $client->{nick} unset a ban for $nick!$user\@$host");
        $self->{channel}->sendToRoom($client, ":$mask MODE $self->{channel}->{name} $modifier$mode $args") if $announce;
        delete $self->{bans}->{$banMask};
    }
    return 1;
}
sub has {
    my $self   = shift;
    my $client = shift;
    foreach(values($self->{bans}->%*)) {
        return 1 if($_->match($client));
    }
    return 0;
}

sub list {
    my $self = shift;
    return $self->{bans};
}

sub level {
    # TODO: -1 => ban?
    # 0 => normal
    # 1 => voice
    # 2 => halfop
    # 3 => op
    # 4 => admin
    # 5 => owner
    return 0;
}
sub symbol {
    return '@';
}

1;
