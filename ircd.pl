#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
use IO::Epoll;
use IO::Socket::INET;
use Data::Dumper;

# ircd modules
use IRCd::Config;
use IRCd::Client;
use IRCd::Log;
use IRCd::Server;
use IRCd::Sockets::Epoll;
use IRCd::Socket;

package IRCd::Run;

sub new {
    my $class = shift;
    my $self  = {
        'config'    => IRCd::Config->new(shift),
        'listener'  => undef,
        'epoll'     => undef,
        'clients'   => undef,

        # ircd internals used across the codebase
        'channels'  => {},
        'host'      => undef,
        'network'   => undef,
        'desc'      => undef,
        'ip'        => undef,
        'port'      => undef,
        'version'   => 0.1,

        # advanced config options
        'pingtimeout' => undef,
        'maxtargets'  => undef,
    };
    bless $self, $class;
    return $self;
}

sub setup {
    my $self = shift;
    $self->{log} = IRCd::Log->new();
    $self->{config}->parse();
    $self->{clientListener} = IO::Socket::INET->new(
        LocalHost => $self->{config}->{ip},
        LocalPort => $self->{config}->{port},
        Listen    => 5,
        ReuseAddr => 1,
    ) or die $!;
    $self->{serverListener} = IO::Socket::INET->new(
        LocalHost => $self->{config}->{ip},
        LocalPort => 6661,
        Listen    => 5,
        ReuseAddr => 1,
    ) or die $!;
    $self->{clientEpoll} = IRCd::Sockets::Epoll->new($self->{clientListener});
    $self->{serverEpoll} = IRCd::Sockets::Epoll->new($self->{serverListener});
    $self->{clients} = {
        id       => {},
        nick     => {}
    };
    $self->{servers} = {
        id       => {},
        name     => {},
    };
    $self->{host}        = $self->{config}->{host};
    $self->{network}     = $self->{config}->{network};
    $self->{desc}        = $self->{config}->{desc};
    $self->{ip}          = $self->{config}->{ip};
    $self->{port}        = $self->{config}->{port};
    $self->{pingtimeout} = $self->{config}->{pingtimeout};
    $self->{maxtargets}  = $self->{config}->{maxtargets};

    $self->{log}->info("Starting cmpctircd");
    $self->{log}->info("==> Host: $self->{host}");
    $self->{log}->info("==> Listening on: $self->{ip}:$self->{port}");
}

sub run {
    my $self = shift;
    while(1) {
        ###               ###
        ###  Client loop  ###
        ###               ###
        $self->clientLoop();

        ###               ###
        ###  Server loop  ###
        ###               ###
        $self->serverLoop();
    }
}

sub clientLoop {
    my $self     = shift;
    my $readable = $self->{clientEpoll}->readable(1000);
    foreach my $event (@$readable) {
        if($event->[0] == fileno($self->{clientListener})) {
            # Accept a new client
            my $newSock = $self->{clientListener}->accept;
            my $newfd   = fileno($newSock);
            my $sockObj = IRCd::Socket->new($newfd, $newSock);
            $self->{clients}->{id}->{$newfd} = $sockObj;
            my $socket  = $self->{clients}->{id}->{$newfd};

            $socket->{client} = IRCd::Client->new(
                'socket' => $socket,
                'ircd'   => $self,
                'config' => $self->{config},
            );
            $socket->{client}->{ip}     = $socket->{sock}->peerhost();
            $socket->{client}->{server} = $self->{host};
            $self->{clientEpoll}->add($newSock);
        } else {
            # Read from an existing client
            my $buffer  = "";
            my $socket   = $self->{clients}->{id}->{$event->[0]};
            $socket->{sock}->recv($buffer, 1024);
            if($buffer eq "") {
                $self->{clientEpoll}->del($socket->{sock});
            } else {
                # Depending on the port, maybe not a Client.
                # But they're a client for now.
                if(!defined $socket->{client}) {
                    # XXX: config could go away?
                    $socket->{client} = IRCd::Client->new((
                        'socket' => $socket,
                        'ircd'   => $self,
                        'config' => $self->{config},
                    ));
                    $socket->{client}->{server} = $self->{host};
                }
                $socket->{client}->{ip} = $socket->{sock}->peerhost();
                my @splitBuffer = split("\r\n", $buffer);
                foreach(@splitBuffer) {
                    $self->{log}->debug("RECV: " . $_);
                    $socket->{client}->parse($_);
                }
            }
        }
    }
    foreach(values($self->{clients}->{id}->%*)) {
        next if(!defined $_->{client});
        $_->{client}->checkTimeout();
    }
}

sub serverLoop {
    my $self     = shift;
    my $readable = $self->{serverEpoll}->readable(1000);
    foreach my $event (@$readable) {
        if($event->[0] == fileno($self->{serverListener})) {
            # Accept a new client
            my $newSock = $self->{serverListener}->accept;
            my $newfd   = fileno($newSock);
            my $sockObj = IRCd::Socket->new($newfd, $newSock);
            $self->{servers}->{id}->{$newfd} = $sockObj;
            my $socket  = $self->{servers}->{id}->{$newfd};

            $socket->{client} = IRCd::Server->new(
                        'socket' => $socket,
                        'ircd'   => $self,
                        'config' => $self->{config},
                    );
            $socket->{client}->{ip}     = $socket->{sock}->peerhost();
            $socket->{client}->{server} = $self->{host};
            $self->{serverEpoll}->add($newSock);
        } else {
            # Read from an existing client
            my $buffer  = "";
            my $socket   = $self->{servers}->{id}->{$event->[0]};
            $socket->{sock}->recv($buffer, 1024);
            if($buffer eq "") {
                $self->{serverEpoll}->del($socket->{sock});
            } else {
                # Depending on the port, maybe not a Client.
                # But they're a client for now.
                if(!defined $socket->{client}) {
                    # XXX: config could go away?
                    $socket->{client} = IRCd::Server->new(
                        'socket' => $socket,
                        'ircd'   => $self,
                        'config' => $self->{config},
                    );
                    $socket->{client}->{server} = $self->{host};
                }
                $socket->{client}->{ip} = $socket->{sock}->peerhost();

                my @splitBuffer = split("\r\n", $buffer, -1);
                my $index       = $#splitBuffer;
                # this code:
                # 1) checks if this read was a complete read or if there was a packet dangling off the end (no \r\n, so the last index isn't blank)
                # 2) if it was a chunked read, adds the dangling packet at the end to the buffer
                # 3) read the buffer if THIS TIME it wasn't a chunked read
                # 4) and when reading, append the newly read packet (first index) to the old buffer
                # 5) parse that new $chunkedPacket (combination of the two, buffer and new packet)
                # 6) parse the rest as normal
                # XXX: "I'm not sure if there's a better way, or if this way would work if there were multiple packets chunked up""
                # XXX: This WILL be revisited and later added for Clients
                if($splitBuffer[$index] ne '') {
                     # Add it to the buffer and then delete it so we don't process it below
                    warn "Adding this to the buffer: $splitBuffer[$index]\r\n";
                    $socket->{client}->{buffer} .= $splitBuffer[$index];
                    $splitBuffer[$index] = '';
                } else {
                    # Only process if this time, it wasn't a chunked read
                    my $chunkedPacket = $socket->{client}->{buffer} . $splitBuffer[0];
                    $self->{log}->debug("CRECV: " . $chunkedPacket);
                    $socket->{client}->parse($chunkedPacket);
                    $splitBuffer[0] = '';
                    $socket->{client}->{buffer} = '';
                }
                for(my $i = 0; $i < @splitBuffer; $i++) {
                    next if($splitBuffer[$i] eq '');
                    $self->{log}->debug("RECV: " . $splitBuffer[$i]);
                    $socket->{client}->parse($splitBuffer[$i]);
                }
            }
        }
    }
}

sub getClientByNick {
    my $self = shift;
    my $nick = shift;
    return $self->{clients}->{nick}->{$nick} if($self->{clients}->{nick}->{$nick});
    return 0;
}


if(!caller) {
    $SIG{PIPE} = sub {
        print STDERR "SIGPIPE @_\n";
    };
    my $ircd = IRCd::Run->new("ircd.xml");
    $ircd->setup;
    $ircd->run;
};
