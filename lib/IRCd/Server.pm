#!/usr/bin/perl
use strict;
use warnings;
no warnings "experimental::postderef"; # for older perls (<5.24)
use feature 'postderef';

use IRCd::Server::Packets;
use IRCd::Constants;

package IRCd::Server;

sub new {
    my ($class, %args) = @_;
    my $self = {
        'socket'         => $args{socket},
        'ircd'           => $args{ircd},
        'config'         => $args{config},
        'buffer'         => '',

        'idle'           => $args{idle}           // 0,
        'lastPong'       => $args{lastPong}       // time(),
        'waitingForPong' => $args{waitingForPong} // 0,
        'sentcaps'       => $args{sentcaps}       // 0,
        'name'           => $args{name}           // "unidentified",
        'sid'            => $args{sid}            // 0,
    };
    $self->{log} = $self->{ircd}->{log};
    bless $self, $class;
    return $self;
}


sub parse {
    my $self = shift;
    my $ircd = $self->{ircd};
    my $msg  = shift;
    my $sock = shift;

    my @splitPacket = split(" ", $msg);

    # Execute any command events for $splitPacket[0]
    my $event      = $ircd->{module}->exec($splitPacket[0], $self, $msg);
    my $foundEvent = $event->{found};

    if(!$foundEvent) {
        $event       = $ircd->{module}->exec($splitPacket[1], $self, $msg);
        $foundEvent  = $event->{found};
    }
    # Check if any of the events returned < 0; if so, return.
    if(!IRCd::Module::can_process($event->{values})) {
        $self->{log}->debug("[$self->{nick}] A handler for $splitPacket[0] returned 0. Bailing out.");
        return;
    }

    # Once we've checked the events, check for a standard function
    # Check if function exists, and if so, call it
    # If client is a server, we'll receive packets like :SID cmd
    my $handlerRef = IRCd::Server::Packets->can(lc($splitPacket[0])) || IRCd::Server::Packets->can(lc($splitPacket[1]));
    if ($handlerRef) {
        $handlerRef->($self, $msg);
    }
    if(!$foundEvent and !$handlerRef) {
        $self->{log}->warn("UNHANDLED PACKET: $msg");
    }
}

sub sync {
    my $self   = shift;
    my $config = $self->{config};
    my $ircd   = $self->{ircd};

    # This method provides for the initial server burst of users and channels
    foreach(keys($self->{ircd}->{clients}->{nick}->%*)) {
        $self->syncUser($_);
    }
    foreach(keys($self->{ircd}->{channels}->%*)) {
        $self->syncChan($_);
    }

    $self->write(":$ircd->{sid} EOS");
    # TODO: sjoin
    # TODO: and join
}

sub syncUser {
    my $self   = shift;
    my $config = $self->{config};
    my $ircd   = $self->{ircd};
    my $user   = shift;
    my $client = $self->{ircd}->{clients}->{nick}->{lc($user)};

    return -1 if(!$client);
    my $sNick  = $client->{nick};
    my $sHop   = 0;
    my $sTime  = time();
    my $sUser  = $client->{ident};
    my $sHost  = $client->{host};
    my $sUID   = $client->{uid};
    my $sServiceStamp = 0;
    my $sUmodes    = "+i";
    my $sVirtHost  = $client->{ip};
    my $sCloakHost = $client->{cloak} // $client->{host};
    my $sIP        = $client->{ip};
    my $sGECOS     = $client->{realname};
    $self->write(":$ircd->{sid} UID $sNick $sHop $sTime $sUser $sHost $sUID $sServiceStamp $sUmodes $sVirtHost $sCloakHost $sIP $sGECOS");
}

sub syncChan {
    my $self   = shift;
    my $config = $self->{config};
    my $ircd   = $self->{ircd};
    my $chan   = shift;
    my $chan_obj = $self->{ircd}->{channels}->{$chan};

    # XXX: need channel create/mod times
    my $time            = time();
    my @presentUsers    = ();
    my $privilegeString = "";

    # :001 SJOIN 1482619970 #services :@00102VE01
    foreach(values($chan_obj->{clients}->%*)) {
        my $uid        = $_->{uid};
        my $userSymbol = $chan_obj->{privilege}->{$chan_obj->getStatus($_)} // "";
        $privilegeString .= "$userSymbol$uid ";
    }
    $self->write(":$ircd->{sid} SJOIN $time $chan :$privilegeString");
}

sub checkTimeout {}
sub disconnect {
    my $self = shift;
    $self->{log}->error("Server ($self->{name}:$self->{sid}) is shutting down?");
    $self->{ircd}->{serverSelector}->del($self->{socket}->{sock});
    $self->{socket}->{sock}->close();
}

sub write {
    my $self = shift;
    my $msg  = shift;
    my $sock;
    my $type;

    $msg .= "\r\n" if($msg !~ /\r\n/);
    if(ref($self->{server}) eq "IRCd::Server") {
        # Write on the appropriate socket
        # XXX: We need UID translation?
        $type = 'server';
        $sock = $self->{server}->{socket}->{sock};
    } else {
        # Dispatch locally
        $type = 'client';
        $sock = $self->{socket}->{sock};
    }
    my $bytes_written = $sock->write($msg);
    if(!$bytes_written) {
        $self->{ircd}->{log}->debug("Looks like a $type (in IRCd::Server) has gone away (no bytes written)");
        $self->disconnect();
    }
}


1;
