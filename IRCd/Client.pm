#!/usr/bin/perl
use strict;
use warnings;
no warnings "experimental::postderef"; # for older perls (<5.24)
use feature 'postderef';

use IRCd::Client::Packets;
use IRCd::Constants;
use IRCd::Modes::User::Cloak;

package IRCd::Client;

sub new {
    my ($class, %args) = @_;
    my $self = {
        'socket'         => $args{socket},
        'ircd'           => $args{ircd},
        'config'         => $args{config},
        'buffer'         => '',

        'idle'           => $args{idle}           // 0,
        'lastPing'       => $args{lastPing}       // 0,
        'lastPong'       => $args{lastPong}       // time(),
        'waitingForPong' => $args{waitingForPong} // 0,
        'registered'     => $args{registered}     // 0,

        'server'         => $args{server}         // undef,
        'nick'           => $args{nick}           // "",
        'ident'          => $args{ident}          // "",
        'realname'       => $args{realname}       // "",

        'ip'             => $args{ip}             // 0,
        'host'           => $args{host}           // 0,
        'uid'            => $args{uid}            // 0,

        'resolve'        => $args{resolve} // IRCd::Resolve->new(),
        'query'          => $args{query}   // undef,

        'modes'          => $args{modes}   // {},
    };
    bless $self, $class;
    $self->{log} = $self->{ircd}->{log};
    # TODO: Default usermodes
    $self->{modes}->{x} = IRCd::Modes::User::Cloak->new($self);
    return $self;
}

sub getMask {
    my $self  = shift;
    my $nick  = $self->{nick}  // "";
    my $ident = $self->{ident} // "";
    my $host  = $self->{host}  // "";
    my $cloak = shift // 0;

    $host = $self->{cloak} if($cloak and $self->{modes}->{x}->has($self));
    return $nick . '!' . $ident . '@' . $host;
}

sub parse {
    my $self = shift;
    my $ircd = $self->{ircd};
    my $msg  = shift;
    my $sock = shift;

    my @splitPacket = split(" ", $msg);

    # TODO: Modular system
    # Check if function exists, and if so, call it
    my %registrationCommands = (
        'user'   => 1,
        'nick'   => 1,
        'pong'   => 1,
        #'cap'   => 1,
        #'pass'  => 1,
    );
    my $requirePong = 0;
    $requirePong = 1 if ($ircd->{config}->{requirepong} and $self->{waitingForPong});
    if (my $handlerRef = IRCd::Client::Packets->can(lc($splitPacket[0]))) {
        # TODO: Registration Timeout error, rather than just ping timeout
        if($ircd->{dns} and $self->{query} and !$self->{host} and !$registrationCommands{lc($splitPacket[0])}) {
            $self->{log}->debug("[$self->{nick}] Waiting to resolve host, blocking");
            return;
        }
        if($requirePong and !$registrationCommands{lc($splitPacket[0])}) {
            $self->{log}->debug("[$self->{nick}] User attempted to register without PONG");
            $self->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTREGISTERED . " * :You have not registered\r\n");
            return;
        }
        if(!$self->{registered} and !$registrationCommands{lc($splitPacket[0])}) {
            $self->{log}->debug("[$self->{nick}] User sent command [$splitPacket[0]] pre-registration");
            $self->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTREGISTERED . " * :You have not registered\r\n");
        }
        # If we're registered and not waiting on a PONG/DNS query...
        $handlerRef->($self, $msg);
    } else {
        $self->{log}->warn("UNHANDLED PACKET: " . $splitPacket[0]);
    }
}

sub sendWelcome {
    my $self = shift;
    my $ircd = $self->{ircd};
    $self->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::RPL_WELCOME  . " $self->{nick} :Welcome to the $ircd->{network} IRC Network $self->{nick}!$self->{ident}\@$self->{ip}\r\n");
    $self->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::RPL_YOURHOST . " $self->{nick} :Your host is $ircd->{host}, running version $ircd->{version}\r\n");
    $self->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::RPL_CREATED  . " $self->{nick} :This server was created on 1/1/1970\r\n");

    # Write MOTD
    my $motd;
    open($motd, "<", "ircd.motd");
    my @motd = <$motd>;
    # TODO: Strip out blank lines?
    $self->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::RPL_MOTDSTART . " $self->{nick} :- $ircd->{host} Message of the Day -\r\n");
    $self->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::RPL_MOTD      . " $self->{nick} :- " . $_ . "\r\n") foreach(@motd);
    $self->{socket}->{sock}->write(":$ircd->{host} " . IRCd::Constants::RPL_ENDOFMOTD . " $self->{nick} :End of /MOTD command.\r\n");
    close($motd);
    $self->{registered} = 1;

    # Tell the servers we're connected to that we exist
    # XXX: HELPER FUNCTIONS!
    # XXX: need sid too
    foreach(values($self->{ircd}->{servers}->{id}->%*)) {
        my $server = $_->{client};
        $self->{log}->debug("[$self->{nick}] Announcing new client to [$server->{name}]");
        $server->syncUser($self->{nick});
    }
}

sub checkTimeout {
    my $self   = shift;
    my $ircd   = $self->{ircd};
    my $mask   = $self->getMask();
    my $period = $self->{lastPong} + $ircd->{pingtimeout};
    my $socket = $self->{socket}->{sock};

    my $requirePong = 0;
    $requirePong = 1 if ($ircd->{config}->{requirepong} and !$self->{lastPing});
    if($requirePong or (time() > $period and !$self->{waitingForPong})) {
        $self->{pingcookie} = $self->createCookie();
        $socket->write("PING :$self->{pingcookie}\r\n");
        $self->{lastPing} = time();
        $self->{waitingForPong} = 1;
    } else {
        #$self->{log}->debug("[$self->{nick}] " . time() . " !> " . $period) if(!$self->{waitingForPong});
    }
    if(time() > ($self->{lastPong} + ($ircd->{pingtimeout} * 2)) and $self->{waitingForPong}) {
        $self->disconnect(1, "Ping timeout");
    } else {
        return if(time() > $period);
        #$self->{log}->debug("[$self->{nick}] " . time() . " !> " . ($self->{lastPong} + ($ircd->{pingtimeout} * 2))) if($self->{waitingForPong});
    }
}

sub checkResolve {
    my $self = shift;
    my $ircd = $self->{ircd};
    my $mask = $self->getMask();
    my $sock = $self->{socket}->{sock};

    if(my $answer = $self->{resolve}->read($self->{query})) {
        # We got an answer to our query!
        $self->{log}->debug("[$self->{nick}] Got an answer to our DNS query for [$self->{ip}]: $answer");
        $self->{host} = $answer;
        $sock->write(":$ircd->{host} NOTICE * :*** Found your hostname\r\n");
        $self->sendWelcome() if($self->{ident} and $self->{nick} and !$self->{registered});
    } elsif($answer < 0) {
        $self->{log}->debug("[$self->{nick}] Query for [$self->{ip}] failed");
        $self->{host} = $self->{ip};
        $sock->write(":$ircd->{host} NOTICE * :*** Could not resolve your hostname: Domain name not found; using your IP address ($self->{ip}) instead.\r\n");
    }
}


sub disconnect {
    my $self     = shift;
    my $ircd     = $self->{ircd};
    my $mask     = $self->getMask();
    my $graceful = shift // 0;
    my $reason   = shift // "Leaving.";
    # Callers are expected to handle the graceful QUIT, or any other
    # parting messages.
    if($graceful) {
        foreach my $chan (keys($ircd->{channels}->%*)) {
            $ircd->{channels}->{$chan}->quit($self, $reason);
        }
        $self->{socket}->{sock}->write(":$mask QUIT :$reason\r\n");
    }
    $self->{socket}->{sock}->close();
    delete $ircd->{clients}->{id}->{$self->{socket}->{fd}};
    delete $ircd->{clients}->{nick}->{$self->{nick}};
}

###                    ###
### Utility functions  ###
###                    ###
sub createCookie {
    my $cookie     = "";
    my @characters = ("A" .. "Z", "a" .. "z", 0.. 9);
    for(my $i = 0; $i < 5; $i++) {
        $cookie .= $characters[rand @characters];
    }
    return $cookie;
}

sub write {
    my $self = shift;
    my $msg  = shift;
    # XXX: differentiate between $self->{server} and the server we reside on?
    $msg .= "\r\n" if($msg !~ /\r\n/);
    if(ref($self->{server}) eq "IRCd::Server") {
        # Write on the appropriate socket
        # XXX: We need UID translation?
        $self->{server}->{socket}->{sock}->write($msg);
    } else {
        # Dispatch locally
        $self->{socket}->{sock}->write($msg);
    }
}


1;
