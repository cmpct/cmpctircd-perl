#!/usr/bin/perl
use strict;
use warnings;
no warnings "experimental::postderef"; # for older perls (<5.24)
use feature 'postderef';
use Term::ANSIColor qw(:constants);

package IRCd::Log;

sub new {
    my $class = shift;
    my $self  = {
        # TODO: perl's current_sub feature
        # TODO: colour switches
        # TODO: Why not just prefix with the calling class and function?
        'ircd'     => shift,
        'colour'   => shift // 1,
        'severity' => uc(shift) // 'DEBUG',

        'levels'   => {
            'ERROR' => 1,
            'WARN'  => 2,
            'INFO'  => 3,
            'DEBUG' => 4,
        },

        'irc_loggers'  => {},
        'file_loggers' => {},
    };
    bless  $self, $class;
    $Term::ANSIColor::AUTORESET = 1;
    return $self;
}

sub shouldLog {
    my $self  = shift;
    my $level = uc(shift);
    return 1 if($self->{levels}->{$level} <= $self->{levels}->{$self->{severity}});
    return 0;
}

sub log {
    my $self    = shift;
    my $level   = shift;
    my $msg     = shift;
    my $colour  = shift;
    my $channel;
    my $file;

    $msg = "[$level]$msg";
    foreach(keys($self->{irc_loggers}->%*)) {
        if($_ eq $level) {
            $channel = $self->{irc_loggers}->{$_};
            if(my $channelObject = $self->{ircd}->{channels}->{$channel}) {
                my $host = $self->{ircd}->{host} // "ircd.internal";
                $channelObject->sendToRoom(0, ":$host PRIVMSG $channel :$msg", $self->{ircd}, 1);
            }
        }
    }
    # XXX: Have file handles in the hash to save the reopening
    foreach(keys($self->{file_loggers}->%*)) {
        if($_ eq $level) {
            $file = $self->{file_loggers}->{$_};
            open(LOGFILE, ">>", $file);
            print LOGFILE $msg . "\r\n";
            close(LOGFILE);
        }
    }
    $colour = Term::ANSIColor::colored($msg . "\r\n", $colour);
    print $colour;
}
sub error {
    my $self = shift;
    my $msg  = shift;
    if($self->shouldLog('error')) {
        my $callerClass    = caller;
        my $callerFunction = (caller 1)[3];
        my $prefix = IRCd::Log::getPrefix($callerClass, $callerFunction);
        $self->log('ERROR', "$prefix $_", 'bold magenta') foreach(split("\r\n", $msg));
    }
}
sub warn {
    my $self = shift;
    my $msg  = shift;
    if($self->shouldLog('warn')) {
        my $callerClass    = caller;
        my $callerFunction = (caller 1)[3];
        my $prefix = IRCd::Log::getPrefix($callerClass, $callerFunction);
        $self->log('WARN', "$prefix $_", 'bright_red') foreach(split("\r\n", $msg));
    }
}

sub info {
    my $self = shift;
    my $msg  = shift;
    if($self->shouldLog('info')) {
        my $callerClass    = caller;
        my $callerFunction = (caller 1)[3];
        my $prefix = IRCd::Log::getPrefix($callerClass, $callerFunction);
        $self->log('INFO', "$prefix $_", 'bright_blue') foreach(split("\r\n", $msg));
    }
}
sub debug {
    my $self = shift;
    my $msg  = shift;
    if($self->shouldLog('debug')) {
        my $callerClass    = caller;
        my $callerFunction = (caller 1)[3];
        my $prefix = IRCd::Log::getPrefix($callerClass, $callerFunction);
        $self->log('DEBUG', "$prefix $_", 'bright_cyan') foreach(split("\r\n", $msg));
    }
}

sub getPrefix {
    # XXX: Why can't we do my($x, $y) for the caller(s)?
    # XXX: Investigate the strange interaction with `caller`.
    my $callerClass    = shift;
    my $callerFunction = shift;
    my $prefix         = "";
    $prefix = "[SERVER]" if($callerClass =~ /server/i or $callerFunction =~ /server/i);
    $prefix = "[CLIENT]" if($callerClass =~ /client/i or $callerFunction =~ /client/i);
    return $prefix;
}

sub methods {
    my $self   = shift;
    my $types  = $self->{ircd}->{config}->{log};
    my $chanObject;
    use Data::Dumper;
    foreach(keys($types->%*)) {
        $self->debug("Got logger type: $_");
        if($_ eq 'irc') {
            if(ref($types->{$_}) eq 'HASH') {
                # Stupid XML bugs mean we need to force it into an array
                my $oldHash = $types->{$_};
                $types->{$_}    = ();
                $types->{$_}[0] = $oldHash;
            }
            foreach($types->{$_}->@*) {
                $self->debug("Got a logger for IRC: $_->{name}");
                $self->{irc_loggers}{$_->{level}} = $_->{name};

                # Create the channel now
                # XXX: Genericise the MODE parser perhaps to allow params in logging config?
                my $chanObject = IRCd::Channel->new($_->{name});
                foreach(split('', $_->{modes})) {
                    next if($_ eq '+');
                    $chanObject->{modes}->{$_}->{set} = 1;
                }
                $self->{ircd}->{channels}->{$_->{name}} = $chanObject;
            }
        } elsif($_ eq 'file') {
            if(ref($types->{$_}) eq 'HASH') {
                # Stupid XML bugs mean we need to force it into an array
                my $oldHash = $types->{$_};
                $types->{$_}    = ();
                $types->{$_}[0] = $oldHash;
            }
            foreach($types->{$_}->@*) {
                $self->debug("Got a logger for a file: $_->{name}");
                $self->{file_loggers}{$_->{level}} = $_->{name};
            }
        } else {
            $self->debug("Found an UNSUPPORTED logger of type: $_");
        }
    }
}


1;
