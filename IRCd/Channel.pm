#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
use IRCd::Constants;
package IRCd::Channel;

sub new {
    my $class = shift;
    my $self  = {
        'name'    => shift,
        'clients' => {},
        'modes'   => ['n', 's'],
        # topic
        # -> ...
    };
    bless $self, $class;
    return $self;
}

sub setMode {
    my $self  = shift;
    my $modes = shift;
    # Check how valid the modes are
    # Another issue is keys.. and other params
    push @{$self->{modes}}, $modes;
}
sub addClient {
    my $self   = shift;
    my $client = shift;
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();
    my $modes  = "";

    if($self->resides($client)) {
        # Already in the channel
        print "They're already in the channel!\r\n";
        return;
    }
    # $client->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::ERR_USERONCHANNEL . " $client->{nick} $self->{name} :is already on channel\r\n");
    $self->{clients}->{$client->{nick}} = $client;
    print "Added client to channel $self->{name}\r\n";

    $self->sendToRoom($client, ":$mask JOIN :$self->{name}");
    foreach(@{$self->{modes}}) {
        print "Adding mode: $_\r\n";
        $modes = $modes . $_;
    }
    $client->{socket}->{sock}->write(":$ircd->{host} MODE $self->{name} +$modes\r\n");
    $client->{socket}->{sock}->write(":$ircd->{host} "  . IRCd::Constants::RPL_NAMREPLY      . " $client->{nick} \@ $self->{name} :\@$_->{nick}\r\n") foreach(values($self->{clients}->%*));
    $client->{socket}->{sock}->write(":$ircd->{host} "  . IRCd::Constants::RPL_ENDOFNAMES    . " $client->{nick} $self->{name} :End of /NAMES list.\r\n");
    $client->{socket}->{sock}->write(":$ircd->{host} "  . IRCd::Constants::RPL_TOPIC         . " $client->{nick} $self->{name} :This is a topic.\r\n");
    $client->{socket}->{sock}->write(":$ircd->{host} "  . IRCd::Constants::RPL_CHANNELMODEIS . " $client->{nick} $self->{name} +$modes\r\n");
    #$client->{socket}->{sock}->write(":$ircd->{host} "  . IRCd::Constants::RPL_CREATIONTIME  . " $client->{nick} $self->{name} " . time() . "\r\n");
}
sub quit {
    my $self   = shift;
    my $client = shift;
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();
    my $msg    = shift;
    if($self->{clients}->{$client->{nick}}) {
        # We should be in the room b/c of the caller but let's be safe.
        print "Removed (QUIT) a client from channel $self->{name}\r\n";
        $self->sendToRoom($client, ":$mask QUIT :$msg");
        delete $self->{clients}->{$client->{nick}};
        return;
    }

}
sub part {
    my $self   = shift;
    my $client = shift;
    my $ircd   = $client->{ircd};
    my $mask   = $client->getMask();
    my $msg    = shift;
    if($self->{clients}->{$client->{nick}}) {
        print "Removed (PART) a client from channel $self->{name}\r\n";
        $self->sendToRoom($client, ":$mask PART $self->{name} :$msg");
        delete $self->{clients}->{$client->{nick}};
        return;
    }
    # If we get here, they weren't in the room.
    # XXX: Is this right?
    $client->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTONCHANNEL . " $self->{name} :You're not on that channel\r\n");
}
sub resides {
    my $self   = shift;
    my $client = shift;
    my $mask   = $client->getMask();
    my $msg    = shift;

    return 1 if ($self->{clients}->{$client->{nick}});
    return 0;
}
sub sendToRoom {
    my $self   = shift;
    my $client = shift;
    my $msg    = shift;
    my $sendToSelf = shift // 1;

    foreach(values($self->{clients}->%*)) {
        next if(($_ eq $client) and !$sendToSelf);
        $_->{socket}->{sock}->write($msg . "\r\n");
    }
}

1;
