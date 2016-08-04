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
    $self->{config}->parse();
    $self->{listener} = IO::Socket::INET->new(
        LocalHost => $self->{config}->{ip},
        LocalPort => $self->{config}->{port},
        Listen    => 5,
        ReuseAddr => 1,
    ) or die $!;
    $self->{epoll} = IRCd::Sockets::Epoll->new($self->{listener});
    $self->{clients} = {
        id       => {},
        nick     => {}
    };
    $self->{host}        = $self->{config}->{host};
    $self->{network}     = $self->{config}->{network};
    $self->{desc}        = $self->{config}->{desc};
    $self->{ip}          = $self->{config}->{ip};
    $self->{port}        = $self->{config}->{port};
    $self->{pingtimeout} = $self->{config}->{pingtimeout};
    $self->{maxtargets}  = $self->{config}->{maxtargets};
}

sub run {
    my $self = shift;
    while(1) {
        my $readable = $self->{epoll}->readable(1000);
        foreach my $event (@$readable) {
            if($event->[0] == fileno($self->{listener})) {
                # Accept a new client
                my $newSock = $self->{listener}->accept;
                my $newfd   = fileno($newSock);
                my $sockObj = IRCd::Socket->new($newfd, $newSock);
                $self->{clients}->{id}->{$newfd} = $sockObj;
                my $socket  = $self->{clients}->{id}->{$newfd};

                $socket->{client} = IRCd::Client->new($socket, $self, $self->{config});
                $socket->{client}->{ip}     = $socket->{sock}->peerhost();
                $socket->{client}->{server} = $self->{host};
                $self->{epoll}->add($newSock);
            } else {
                # Read from an existing client
                my $buffer  = "";
                my $socket   = $self->{clients}->{id}->{$event->[0]};
                $socket->{sock}->recv($buffer, 1024);
                if($buffer eq "") {
                    $self->{epoll}->del($socket->{sock});
                } else {
                    if($buffer =~ /\r\n/) {
                        print "RECV: " . $buffer;
                    } else {
                        print "RECV: " . $buffer . "\r\n";
                    }
                    # Depending on the port, maybe not a Client.
                    # But they're a client for now.
                    if(!defined $socket->{client}) {
                        # XXX: config could go away?
                        $socket->{client} = IRCd::Client->new($socket, $self, $self->{config});
                        $socket->{client}->{server} = $self->{host};
                    }
                    $socket->{client}->{ip} = $socket->{sock}->peerhost();
                    my @splitBuffer = split("\r\n", $buffer);
                    foreach(@splitBuffer) {
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
