#!/usr/bin/perl
use strict;
use warnings;
use Term::ANSIColor qw(:constants);
#use feature 'current_sub';

package IRCd::Log;

sub new {
    my $class = shift;
    my $self  = {
        # TODO: write to file
        # TODO: colour switches
        # TODO: Why not just prefix with the calling class and function?
        'filename' => shift // 'cmpctircd.log',
        'colour'   => shift // 1,
        'severity' => shift // 'DEBUG',

        'levels'   => {
            'ERROR' => 1,
            'WARN'  => 2,
            'INFO'  => 3,
            'DEBUG' => 4,
        },
    };
    bless  $self, $class;
    return $self;
}

sub shouldLog {
    my $self  = shift;
    my $level = uc(shift);
    return 1 if($self->{levels}->{$level} <= $self->{levels}->{$self->{severity}});
    return 0;
}

sub error {
    my $self = shift;
    my $msg  = shift;
    if($self->shouldLog('error')) {
        my $callerClass    = caller;
        my $callerFunction = (caller 1)[3];
        my $prefix = IRCd::Log::getPrefix($callerClass, $callerFunction);
        print Term::ANSIColor::colored("[ERROR]$prefix "  . $_ . "\r\n", 'bold magenta') foreach(split("\r\n", $msg));
    }
}
sub warn {
    my $self = shift;
    my $msg  = shift;
    if($self->shouldLog('warn')) {
        my $callerClass    = caller;
        my $callerFunction = (caller 1)[3];
        my $prefix = IRCd::Log::getPrefix($callerClass, $callerFunction);
        print Term::ANSIColor::colored("[WARN] $prefix "  . $_ . "\r\n", 'bright_red') foreach(split("\r\n", $msg));
    }
}

sub info {
    my $self = shift;
    my $msg  = shift;
    if($self->shouldLog('info')) {
        my $callerClass    = caller;
        my $callerFunction = (caller 1)[3];
        my $prefix = IRCd::Log::getPrefix($callerClass, $callerFunction);
        print Term::ANSIColor::colored("[INFO] $prefix "  . $_ . "\r\n", 'bright_blue') foreach(split("\r\n", $msg));
    }
}
sub debug {
    my $self = shift;
    my $msg  = shift;
    if($self->shouldLog('debug')) {
        my $callerClass    = caller;
        my $callerFunction = (caller 1)[3];
        my $prefix = IRCd::Log::getPrefix($callerClass, $callerFunction);
        print Term::ANSIColor::colored("[DEBUG]$prefix " . $_ . "\r\n", 'bright_cyan') foreach(split("\r\n", $msg));
    }
}

sub getPrefix {
    # XXX: Why can't we do my($x, $y) for the caller(s)?
    # XXX: Investigate the strange interaction with `caller`.
    my $callerClass    = shift;
    my $callerFunction = shift;
    my $prefix         = "";
    $prefix = " [SERVER]" if($callerClass =~ /server/i or $callerFunction =~ /server/i);
    $prefix = " [CLIENT]" if($callerClass =~ /client/i or $callerFunction =~ /client/i);
    return $prefix;
}


1;
