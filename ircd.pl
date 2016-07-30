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
use IRCd::Epoll;
use IRCd::Socket;

package IRCd::Run;

sub new {
    my $class = shift;
    my $self  = {
        'config'    => IRCd::Config->new(shift),
        'listener'  => undef,
        'epoll'     => undef,
        'clientMap' => undef,

        # ircd internals used across the codebase
        'channels'  => {},
        'host'      => undef,
        'network'   => undef,
        'ip'        => undef,
        'port'      => undef,
        'version'   => 0.1,

        # advanced config options
        'maxtargets' => undef,
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
    $self->{epoll} = IRCd::Epoll->new($self->{listener});
    $self->{clientMap} = ();

    $self->{host}       = $self->{config}->{host};
    $self->{network}    = $self->{config}->{network};
    $self->{ip}         = $self->{config}->{ip};
    $self->{port}       = $self->{config}->{port};
    $self->{maxtargets} = $self->{config}->{maxtargets};
}

sub run {
    my $self = shift;
    while(1) {
        my $readable = $self->{epoll}->getReadable(-1);
        foreach my $event (@$readable) {
            if($event->[0] == fileno($self->{listener})) {
                # Accept a new client
                my $newSock = $self->{listener}->accept;
                my $newfd   = fileno($newSock);
                my $sockObj = IRCd::Socket->new(sock => $newSock, fd => $newfd);
                $self->{clientMap}->{$newfd} = $sockObj;
                $self->{epoll}->addSock($newSock);
            } else {
                # Read from an existing client
                my $buffer  = "";
                my $socket   = $self->{clientMap}->{$event->[0]};
                $socket->{sock}->recv($buffer, 1024);
                if($buffer eq "") {
                    print "Removing a client...\r\n";
                    $self->{epoll}->delSock($socket->{sock});
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
                    }
                    $socket->{client}->{ip} = $socket->{sock}->peerhost();
                    my @splitBuffer = split("\r\n", $buffer);
                    foreach(@splitBuffer) {
                        $socket->{client}->parse($_);
                    }
                }
            }
        }
    }
}
sub getClientByNick {
    my $self = shift;
    my $nick = shift;
    foreach(values($self->{clientMap}->%*)) {
        #use Data::Dumper;
        #print Dumper($_->{client});
        return $_->{client} if($_->{client}->{nick} eq $nick);
    }
    return 0;
}


if(!caller) {
    my $ircd = IRCd::Run->new("ircd.xml");
    $ircd->setup;
    $ircd->run;
};
