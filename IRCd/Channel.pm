#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;

package IRCd::Channel;

sub new {
    my $class = shift;
    my $self  = {
        'name'    => shift,
        'clients' => [],
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
    my $mask  = $client->getMask();
    my $modes = "";

    if($self->resides($client)) {
        # Already in the channel
        print "They're already in the channel!\r\n";
        return;
    }
    # $client->{socket}->{sock}->write(":$client->{config}->{host} 443 $client->{nick} $self->{name} :is already on channel\r\n");

    push @{$self->{clients}}, $client;
    print "Added client to channel $self->{name}\r\n";

    $self->sendToRoom($client, ":$mask JOIN :$self->{name}");
    foreach(@{$self->{modes}}) {
        print "Adding mode: $_\r\n";
        $modes = $modes . $_;
    }
    $client->{socket}->{sock}->write(":$client->{config}->{host} MODE $self->{name} +$modes\r\n");
    foreach($self->{clients}->@*) {
        # RPL_NAMEREPLY
        $client->{socket}->{sock}->write(":$client->{config}->{host} 353 $client->{nick} \@ $self->{name} :\@$_->{nick}\r\n");
    }
    # RPL_ENDOFNAMES
    $client->{socket}->{sock}->write(":$client->{config}->{host} 366 $client->{nick} $self->{name} :End of /NAMES list.\r\n");
    # RPL_TOPIC
    $client->{socket}->{sock}->write(":$client->{config}->{host} 332 $client->{nick} $self->{name} :This is a topic.\r\n");
    $client->{socket}->{sock}->write(":$client->{config}->{host} 324 $client->{nick} $self->{name} +$modes\r\n");
    #$client->{socket}->{sock}->write(":$client->{config}->{host} 329 $client->{nick} $self->{name} " . time() . "\r\n");
}
sub quit {
    my $self   = shift;
    my $client = shift;
    my $mask   = $client->getMask();
    my $msg    = shift;
    foreach(@{$self->{clients}}) {
        # We should be in the room b/c of the caller but let's be safe.
        if($_ eq $client) {
            print "Removed (QUIT) a client from channel $self->{name}\r\n";
            $self->sendToRoom($client, ":$mask QUIT :$msg");
            @{$self->{clients}} = grep { $_ != $client } @{$self->{clients}};
            return;
        }
    }

}
sub part {
    my $self   = shift;
    my $client = shift;
    my $mask   = $client->getMask();
    my $msg    = shift;
    foreach(@{$self->{clients}}) {
        # We should be in the room b/c of the caller but let's be safe.
        if($_ eq $client) {
            @{$self->{clients}} = grep { $_ != $client } @{$self->{clients}};
            print "Removed (PART) a client from channel $self->{name}\r\n";
            $self->sendToRoom($client, ":$mask PART $self->{name} :$msg");
            return;
        }
    }
    # If we get here, they weren't in the room.
    # XXX: Is this right?
    $client->{socket}->{sock}->write(":$client->{config}->{host} 442 $self->{name} :You're not on that channel\r\n");
}
sub resides {
    my $self   = shift;
    my $client = shift;
    my $mask   = $client->getMask();
    my $msg    = shift;

    foreach($self->{clients}->@*) {
        return 1 if($_ eq $client);
    }
    return 0;
}
sub sendToRoom {
    my $self   = shift;
    my $client = shift;
    my $msg    = shift;
    my $sendToSelf = shift // 1;

    foreach($self->{clients}->@*) {
        next if(($_ eq $client) and !$sendToSelf);
        $_->{socket}->{sock}->write($msg . "\r\n");
    }
}

1;
