#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
no warnings "experimental::postderef"; # for older perls (<5.24)
use feature 'postderef';

use Getopt::Long;
use IO::Epoll;
use IO::Socket::INET;
use DateTime;

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
    # TODO: Make a listener hash so we can have many of each
    $self->{clientListener} = IO::Socket::INET->new(
        LocalHost => $self->{config}->{ip},
        LocalPort => $self->{config}->{port},
        Listen    => 5,
        ReuseAddr => 1,
    ) or die $!;
    $self->{clientListener}->blocking(0);
    $self->{serverListener} = IO::Socket::INET->new(
        LocalHost => $self->{config}->{ip},
        LocalPort => 6661,
        Listen    => 5,
        ReuseAddr => 1,
    ) or die $!;
    $self->{serverListener}->blocking(0);
    if($self->{config}->{tls}) {
        require IO::Socket::SSL;
        $self->{clientTLSListener} = IO::Socket::SSL->new(
            LocalHost     => $self->{config}->{ip},
            LocalPort     => $self->{config}->{tlsport},
            SSL_cert_file => 'tls_cert.pem',
            SSL_key_file  => 'tls_key.pem',
            Listen        => 5,
            ReuseAddr     => 1,
        ) or die $!;
        $self->{clientTLSListener}->blocking(0);
        $self->{clientTLSSelector} = $self->{config}->getSockProvider($self->{clientTLSListener});
    }
    $self->{clientSelector} = $self->{config}->getSockProvider($self->{clientListener});
    $self->{serverSelector} = $self->{config}->getSockProvider($self->{serverListener});
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
    $self->{cloak_keys}  = $self->{config}->{cloak_keys};
    $self->{dns}         = $self->{config}->{dns};
    $self->{pingtimeout} = $self->{config}->{pingtimeout};
    $self->{maxtargets}  = $self->{config}->{maxtargets};
    $self->{create_time} = DateTime->now;
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
        $self->clientLoop($self->{clientListener}, $self->{clientSelector}, 1024);

        ###              ###
        ### Client (TLS) ###
        ###     loop     ###
        ###              ###
        if($self->{clientTLSListener}) {
            # http://search.cpan.org/~sullr/IO-Socket-SSL-2.036/lib/IO/Socket/SSL.pod#Common_Usage_Errors
            $self->clientLoop($self->{clientTLSListener}, $self->{clientTLSSelector}, 16000, 1);
        }

        ###               ###
        ###  Server loop  ###
        ###               ###
        $self->serverLoop($self->{serverListener}, $self->{serverSelector}, 1024);
    }
}

sub clientLoop {
    my $self     = shift;
    my $listener = shift;
    my $selector = shift;
    my $bytes    = shift // 1024;
    my $tls      = shift // 0;

    my @readable = $selector->readable(1000);
    foreach my $event (@readable) {
        # This is needed because of the way that IO::Epoll vs IO::Socket return handles (or fds)
        $event = fileno($event) if(ref($event) eq 'IO::Socket::INET');
        $event = $event->[0]    if(ref($event) eq 'ARRAY');
        if($event == fileno($listener)) {
            # Accept a new client
            my $newSock = $listener->accept;
            my $newfd   = fileno($newSock);
            my $sockObj = IRCd::Socket->new($newfd, $newSock);
            $self->{clients}->{id}->{$newfd} = $sockObj;
            my $socket  = $self->{clients}->{id}->{$newfd};

            $socket->{client} = IRCd::Client->new(
                'socket' => $socket,
                'ircd'   => $self,
                'config' => $self->{config},
                'tls'    => $tls,
            );
            $socket->{client}->{ip}     = $socket->{sock}->peerhost();
            $socket->{client}->{server} = $self->{host};
            if($self->{dns}) {
                $socket->{sock}->write(":$self->{host} NOTICE * :*** Looking up your hostname...\r\n");
                $socket->{client}->{query} = $socket->{client}->{resolve}->fire($socket->{client}->{ip});
            } else {
                # TODO: Could have a 'no DNS resolve enabled' message here.
                # TODO: I think some servers do it?
            }
            $selector->add($newSock);
        } else {
            # Read from an existing client
            my $buffer  = "";
            my $socket   = $self->{clients}->{id}->{$event};
            return if(!$socket);

            sysread($socket->{sock}, $buffer, $bytes);
            if($buffer eq "") {
                $selector->del($socket->{sock});
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
        $_->{client}->checkResolve() if($self->{dns});
    }
}

sub serverLoop {
    my $self     = shift;
    my $listener = shift;
    my $selector = shift;
    my $bytes    = shift // 1024;
    my $tls      = shift // 0;

    my @readable = $selector->readable(1000);
    foreach my $event (@readable) {
        # This is needed because of the way that IO::Epoll vs IO::Socket return handles (or fds)
        $event = fileno($event) if(ref($event) eq 'IO::Socket::INET');
        $event = $event->[0]    if(ref($event) eq 'ARRAY');
        if($event == fileno($listener)) {
            # Accept a new client
            my $newSock = $listener->accept;
            my $newfd   = fileno($newSock);
            my $sockObj = IRCd::Socket->new($newfd, $newSock);
            $self->{servers}->{id}->{$newfd} = $sockObj;
            my $socket  = $self->{servers}->{id}->{$newfd};

            $socket->{client} = IRCd::Server->new(
                        'socket' => $socket,
                        'ircd'   => $self,
                        'config' => $self->{config},
                        'tls'    => $tls,
            );
            $socket->{client}->{ip}     = $socket->{sock}->peerhost();
            $socket->{client}->{server} = $self->{host};
            $selector->add($newSock);
        } else {
            # Read from an existing client
            my $buffer  = "";
            my $socket   = $self->{servers}->{id}->{$event};
            return if(!$socket);

            sysread($socket->{sock}, $buffer, $bytes);
            if($buffer eq "") {
                $selector->del($socket->{sock});
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
    my $config = "/etc/cmpctircd/ircd.xml";
    Getopt::Long::GetOptions(
        "config=s" => \$config,
    );
    if(!-e $config) {
        die "Config file [$config] does not exist! Please create it and try again.\r\n";
    }
    my $ircd = IRCd::Run->new($config);
    $ircd->setup;
    $ircd->run;
};
