#!/usr/bin/perl
use strict;
use warnings;
no warnings "experimental::postderef"; # for older perls (<5.24)
use feature 'postderef';

use IRCd::Client::Packets;
use IRCd::Constants;
use IRCd::Modes::User::Cloak;
use IRCd::Modes::User::IRCOp;
use IRCd::Modes::User::TLS;

package IRCd::Client;

sub new {
    my ($class, %args) = @_;
    my $self = {
        'socket'         => $args{socket},
        'ircd'           => $args{ircd},
        'config'         => $args{config},
        'buffer'         => '',
        'tls'            => $args{tls}            // 0,

        'idle'           => $args{idle}           // time(),
        'lastPing'       => $args{lastPing}       // 0,
        'lastPong'       => $args{lastPong}       // time(),
        'waitingForPong' => $args{waitingForPong} // 0,
        'registered'     => $args{registered}     // 0,
        'signonTime'     => $args{signonTime}     // time(),

        'away'           => $args{away}           // "",

        'server'         => $args{server}         // undef,
        'nick'           => $args{nick}           // "",
        'ident'          => $args{ident}          // "",
        'realname'       => $args{realname}       // "",

        'ip'             => $args{ip}             // 0,
        'host'           => $args{host}           // 0,
        'uid'            => $args{uid}            // IRCd::Client::createUID(),
        'disconnect'     => $args{disconnect}     // 0,

        'resolve'        => $args{resolve} // undef,
        'query'          => $args{query}   // undef,

        'modes'          => $args{modes}   // {},
    };
    bless $self, $class;
    $self->{ircd}->{clients}->{uid}->{lc($self->{uid})} = $self;
    $self->{log}        = $self->{ircd}->{log};
    $self->{resolve}    = IRCd::Resolve->new($self);
    $self->{modes}->{o} = IRCd::Modes::User::IRCOp->new($self);
    $self->{modes}->{x} = IRCd::Modes::User::Cloak->new($self);
    $self->{modes}->{z} = IRCd::Modes::User::TLS->new($self);
    return $self;
}

sub getMask {
    # XXX: become get_mask
    my $self  = shift;
    my $nick  = $self->{nick}  // "";
    my $ident = $self->{ident} // "";
    my $host  = $self->{host}  // "";
    my $cloak = shift // 0;

    $host = $self->{cloak} if($cloak and $self->{modes}->{x}->has($self));
    return $nick . '!' . $ident . '@' . $host;
}

sub get_host {
    my $self  = shift;
    my $cloak = shift // 0;
    if($cloak) {
        return $self->{cloak} // $self->{host} // $self->{ip};
    } else {
        return $self->{host} // $self->{ip};
    }
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
        'USER'   => 1,
        'NICK'   => 1,
        'PONG'   => 1,
        #'CAP'   => 1,
        #'PASS'  => 1,
    );
    my $requirePong = 0;
    $requirePong = 1 if ($ircd->{config}->{requirepong} and $self->{waitingForPong});

    # Execute any command events for $splitPacket[0]
    my $event      = $ircd->{module}->exec($splitPacket[0], $self, $msg);
    my $foundEvent = $event->{found};
    # Check if any of the events returned < 0; if so, return.
    if(!IRCd::Module::can_process($event->{values})) {
        $self->{log}->debug("[$self->{nick}] A handler for $splitPacket[0] returned 0. Bailing out.");
        return;
    }
    my $handlerRef = IRCd::Client::Packets->can(lc($splitPacket[0]));
    if($handlerRef) {
        # TODO: Registration Timeout error, rather than just ping timeout
        if($ircd->{dns} and $self->{query} and !$self->{host} and !$registrationCommands{uc($splitPacket[0])}) {
            $self->{log}->debug("[$self->{nick}] Waiting to resolve host, blocking");
            return;
        }
        if(!$self->{registered} and $requirePong and !$registrationCommands{uc($splitPacket[0])}) {
            $self->{log}->debug("[$self->{nick}] User attempted to register without PONG");
            $self->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTREGISTERED . " * :You have not registered");
            return;
        }
        if(!$self->{registered} and !$registrationCommands{uc($splitPacket[0])}) {
            $self->{log}->debug("[$self->{nick}] User sent command [$splitPacket[0]] pre-registration");
            $self->write(":$ircd->{host} " . IRCd::Constants::ERR_NOTREGISTERED . " * :You have not registered");
            return;
        }
        my %idleCommands = (
            'PONG'  => 1,
            'PING'  => 1,
            'WHOIS' => 1,
            'WHO'   => 1,
            'MODE'  => 1, # ZNC sends MODE +i when I reattach (bz #135)
            'NAMES' => 1,
            'AWAY'  => 1,
        );
        if (!$idleCommands{uc($splitPacket[0])}) {
            $self->{idle} = time();
        }
        # If we're registered and not waiting on a PONG/DNS query...
        $handlerRef->($self, $msg);
    }
    if(!$foundEvent and !$handlerRef) {
        $self->write(":$ircd->{host} " . IRCd::Constants::ERR_UNKNOWNCOMMAND . " $self->{nick} $splitPacket[0] :Unknown command");
        $self->{log}->warn("UNHANDLED PACKET: " . $splitPacket[0]);
    }
}

sub sendWelcome {
    my $self        = shift;
    my $ircd        = $self->{ircd};
    my $create_time = $ircd->{create_time};
    my $create_str  = sprintf("%s %u %u at %s", $create_time->month_abbr(),
                        $create_time->day(), $create_time->year(),
                        $create_time->hms);
    $self->write(":$ircd->{host} " . IRCd::Constants::RPL_WELCOME  . " $self->{nick} :Welcome to the $ircd->{network} IRC Network $self->{nick}!$self->{ident}\@" . $self->get_host());
    $self->write(":$ircd->{host} " . IRCd::Constants::RPL_YOURHOST . " $self->{nick} :Your host is $ircd->{host}, running version cmpctircd-$ircd->{version}");
    $self->write(":$ircd->{host} " . IRCd::Constants::RPL_CREATED  . " $self->{nick} :This server was created $create_str");
    # XXX: Generate the user/chan modes programatically
    #$self->write(":$ircd->{host} " . IRCd::Constants::RPL_MYINFO   . " $self->{nick} $ircd->{host} cmpctircd-$ircd->{version} x ntlo\r\n");
    # https://github.com/grawity/irc-docs/blob/master/client/RPL_ISUPPORT/draft-hardy-irc-isupport-00.txt#L462-L475
    $self->write(":$ircd->{host} " . IRCd::Constants::RPL_ISUPPORT . " $self->{nick} CASEMAPPING=rfc1459 PREFIX=(ov)\@+ STATUSMSG=\@+ NETWORK=$ircd->{network} MAXTARGETS=$ircd->{maxtargets} :are supported by this server");
    $self->write(":$ircd->{host} " . IRCd::Constants::RPL_ISUPPORT . " $self->{nick} CHANTYPES=# CHANMODES=b,,l,ntm :are supported by this server");
    $self->motd();
    $self->{registered} = 1;

    # Tell the servers we're connected to that we exist
    # XXX: HELPER FUNCTIONS!
    # XXX: need sid too
    foreach(values($self->{ircd}->{servers}->{id}->%*)) {
        my $server = $_->{client};
        $self->{log}->debug("[$self->{nick}] Announcing new client to [$server->{name}]");
        $server->syncUser($self->{nick});
    }

    # Set initial modes
    # anonymous function to set, is independent of the XML hash logic
    my $setter = sub {
        my $self  = shift;
        my $name  = shift;
        my $param = shift;
        if(ref($param) eq 'HASH') {
            $param = "";
        }
        # we need to pass the client, otherwise the mode setting won't have a user to ref to
        $self->{modes}->{$name}->grant($self, "+", $name, $param // undef, 1, 1);
    };
    # Set initial modes
    foreach my $userModes (values($ircd->{config}->{usermodes}->%*)) {
        # XXX: if there's only one mode, XML::Simple doesn't make 'name' the key (workaround)
        if($userModes->{name}) {
            $setter->($self, $userModes->{name}, $userModes->{param});
        } else {
            foreach(keys($userModes->%*)) {
                $setter->($self, $_, $userModes->{$_}->{param});
            }
        }
    }
    $self->{modes}->{z}->grant() if ($self->{tls});
}

sub motd {
    my $self = shift;
    my $ircd = $self->{ircd};
    my $motd;
    open($motd, "<", $ircd->{motd_path});
    my @motd = <$motd>;
    $self->write(":$ircd->{host} " . IRCd::Constants::RPL_MOTDSTART . " $self->{nick} :- $ircd->{host} Message of the Day -");
    for (my $i = 0; $i < @motd; $i++) {
        my $line = $motd[$i];
        $line =~ s/\r?\n//;
        last if ($i + 1 == @motd && $line =~ /^\s*$/);
        $self->write(":$ircd->{host} " . IRCd::Constants::RPL_MOTD     . " $self->{nick} :- " . $line);
    }
    $self->write(":$ircd->{host} " . IRCd::Constants::RPL_ENDOFMOTD . " $self->{nick} :End of /MOTD command.");
    close($motd);
}

sub rules {
    my $self = shift;
    my $ircd = $self->{ircd};
    my $rules;
    open($rules, "<", $ircd->{rules_path});
    my @rules = <$rules>;
    $self->write(":$ircd->{host} " . IRCd::Constants::RPL_RULESSTART . " $self->{nick} :- $ircd->{host} server rules -");
    for (my $i = 0; $i < @rules; $i++) {
        my $line = $rules[$i];
        $line =~ s/\r?\n//;
        last if ($i + 1 == @rules && $line =~ /^\s*$/);
        $self->write(":$ircd->{host} " . IRCd::Constants::RPL_RULES      . " $self->{nick} :- " . $line);
    }
    $self->write(":$ircd->{host} " . IRCd::Constants::RPL_ENDOFRULES . " $self->{nick} :End of RULES command.");
    close($rules);
}

sub checkTimeout {
    my $self   = shift;
    my $ircd   = $self->{ircd};
    my $mask   = $self->getMask(1);
    my $period = $self->{lastPong} + $ircd->{pingtimeout};

    my $requirePong = 0;
    $requirePong = 1 if ($ircd->{config}->{requirepong} and !$self->{lastPing});
    if($requirePong or (time() > $period and !$self->{waitingForPong})) {
        $self->{pingcookie} = $self->createCookie();
        $self->write("PING :$self->{pingcookie}");
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
    my $mask = $self->getMask(1);
    my $sock = $self->{socket}->{sock};
    my $answer = 0;

    return if($self->{host} eq $self->{ip});
    return if($self->{registered});
    if($answer = $self->{resolve}->read($self->{query}) and $answer ne 'ERROR') {
        # We got an answer to our query!
        $self->{log}->debug("[$self->{nick}] Got an answer to our DNS query for [$self->{ip}]: $answer");
        $self->{host} = $answer;
        $self->write(":$ircd->{host} NOTICE * :*** Found your hostname");
        $self->sendWelcome() if($self->{ident} and $self->{nick} and !$self->{registered});
    } elsif(((time() - $self->{dns_time}) > $self->{ircd}->{config}->{dnstimeout}) or ($self->{query} eq 'ERROR')) {
        $self->{log}->debug("[$self->{nick}] Query for [$self->{ip}] failed");
        $self->{host} = $self->{ip};
        $self->write(":$ircd->{host} NOTICE * :*** Could not resolve your hostname: Domain name not found; using your IP address ($self->{ip}) instead.");
        $self->sendWelcome() if($self->{ident} and $self->{nick} and !$self->{registered});
    }
}


sub disconnect {
    my $self     = shift;
    my $ircd     = $self->{ircd};
    my $mask     = $self->getMask(1);
    my $graceful = shift // 0;
    my $reason   = shift // "Leaving.";

    # Callers are expected to handle the graceful QUIT, or any other
    # parting messages.
    if($graceful) {
        foreach my $chan (keys($ircd->{channels}->%*)) {
            next if(!$ircd->{channels}->{$chan}->{clients}->{lc($self->{nick})});
            $ircd->{channels}->{$chan}->quit($self, $reason);
        }
        $self->write(":$mask QUIT :$reason");
    }

    if(ref($self->{server}) eq "IRCd::Server") {
        delete $self->{server}->{clients}->{nick}->{lc($self->{nick})};
    }
    $self->{ircd}->{clientSelector}->del($self->{socket}->{sock});
    $self->{socket}->{sock}->close();
    delete $ircd->{clients}->{id}->{$self->{socket}->{fd}};
    delete $ircd->{clients}->{nick}->{lc($self->{nick})};
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
    my $sock;

    if($self->{disconnected}) {
        $self->{log}->debug(caller . " attempted to write on a dead client");
        return;
    }
    $msg .= "\r\n" if($msg !~ /\r\n/);

    # Write on the appropriate socket
    if(ref($self->{server}) eq "IRCd::Server") {
        # UID translation (change nicks -> UIDs)
        my @splitMessage = split(" ", $msg);
        if($splitMessage[0] !~ /^:0/) {
            $self->{log}->debug("$splitMessage[0] needs to be translated to a UID...");

            # Delete everything after the ! to get a nick
            $splitMessage[0] =~ s/!.*//s;
            $splitMessage[0] =~ s/://;
            if($splitMessage[0] ne $self->{ircd}->{host}) {
                $self->{log}->debug("Looking for the client named $splitMessage[0]");
                $splitMessage[0] = $self->{ircd}->getClientByNick($splitMessage[0]);

                return 0 if(!$splitMessage[0]);
                $splitMessage[0] = $splitMessage[0]->{uid};
                $msg = join(' ', @splitMessage) . "\r\n";
            }
        }
        $sock = $self->{server}->{socket}->{sock};
    } else {
        # Dispatch locally
        $sock = $self->{socket}->{sock};
    }
    my $bytes_written = $sock->write($msg);
    if(!$bytes_written) {
        $self->{ircd}->{log}->debug("Looks like a client (in IRCd::Client) has gone away (no bytes written)");
        $self->{disconnect} = 1;
    }
}

sub getModeStrings {
    my $self        = shift;
    my $characters  = shift // "+";
    my $modes       = "";
    my $args        = "";
    foreach(keys($self->{modes}->%*)) {
        my $provides = $self->{modes}->{$_}->{provides};
        my $value    = $self->{modes}->{$_}->get();
        if($value > 0 and $value ne '') {
            $characters .= $provides;
            if($self->{modes}->{$_}->{hasparam}) {
                $args       .= $value . " ";
            }
        }
    }
    return {
        'characters' => $characters,
        'args'       => $args,
    };
}

sub createUID {
    use 5.010;
    state $uid_counter = 0;
    $uid_counter++;

    if($uid_counter == 36 ** 2) {
        $uid_counter = 0;
    }

    my $rand = sub {
        my $data;
        for(my $i = 0; $i < 8; $i++) {
            $data .= chr(int(rand() * 256));
        }
        return $data;
    };
    my $UID = sprintf("%s%c%c%c%c%c%c",
        0, # unrealircd's 'me.id'
        IRCd::Client::uid_int_to_char($rand % 36),
        IRCd::Client::uid_int_to_char($rand % 36),
        IRCd::Client::uid_int_to_char($rand % 36),
        IRCd::Client::uid_int_to_char($rand % 36),
        IRCd::Client::uid_int_to_char($uid_counter / 36),
        IRCd::Client::uid_int_to_char($uid_counter % 36),
    );
    return $UID;
}

sub uid_int_to_char {
    my $char = shift;
    # XXX: This is so wrong.
    # XXX: https://github.com/unrealircd/unrealircd/blob/8da3e3e1bc8e582b8696a9411c7de3abbe382893/src/uid.c#L32
    if($char < 10) {
        return ord('0') + $char;
    } else {
        return (ord('A') + $char) - 10;
    }
}


1;
