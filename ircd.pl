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
    # XXX: Should we remove 'id' and have an idToFd function?
    $self->{clients} = {
        id       => {},
        uid      => {},
        nick     => {}
    };
    $self->{servers} = {
        id       => {},
        sid      => {},
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
                $socket->{client}->{ip} = $socket->{sock}->peerhost();

                # Thanks to john for figuring this out
                # Append the client's buffer with newly read packets
                # Extract every message ending with \r\n
                # Remove messages ending with \r\n from the client's buffer
                # Parse the successful (properly delimited) messages
                $socket->{client}->{buffer} .= $buffer;
                my @result = $socket->{client}->{buffer} =~ /(.*?)\r\n/g;
                $socket->{client}->{buffer} =~ s/(.*?)\r\n//g;
                foreach(@result) {
                    next if($_ eq '');
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
                $socket->{client}->{ip} = $socket->{sock}->peerhost();

                # Thanks to john for figuring this out
                # Append the client's buffer with newly read packets
                # Extract every message ending with \r\n
                # Remove messages ending with \r\n from the client's buffer
                # Parse the successful (properly delimited) messages
                $socket->{client}->{buffer} .= $buffer;
                my @result = $socket->{client}->{buffer} =~ /(.*?)\r\n/g;
                $socket->{client}->{buffer} =~ s/(.*?)\r\n//g;
                foreach(@result) {
                    next if($_ eq '');
                    $self->{log}->debug("RECV: " . $_);
                    $socket->{client}->parse($_);
                }
            }
        }
    }
}

sub getClientByNick {
    my $self = shift;
    my $nick = lc(shift);
    # First attempt a local search...
    return $self->{clients}->{nick}->{$nick} if($self->{clients}->{nick}->{$nick});
    # Then check our connected servers...
    # XXX: we'll need a hunt_server in time for hops > 0
    foreach(values($self->{servers}->{sid}->%*)) {
        return $_->{clients}->{nick}->{$nick} if($_->{clients}->{nick}->{$nick});
    }
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
