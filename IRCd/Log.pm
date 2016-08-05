#!/usr/bin/perl
use strict;
use warnings;
use Term::ANSIColor qw(:constants);
use feature 'current_sub';

package IRCd::Log;

sub new {
    my $class = shift;
    my $self  = {
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
        print Term::ANSIColor::colored("[ERROR] "  . $_ . "\r\n", 'bold magenta') foreach(split("\r\n", $msg));
    }
}
sub warn {
    my $self = shift;
    my $msg  = shift;
    if($self->shouldLog('warn')) {
        print Term::ANSIColor::colored("[WARN] "  . $_ . "\r\n", 'bright_red') foreach(split("\r\n", $msg));
    }
}

sub info {
    my $self = shift;
    my $msg  = shift;
    if($self->shouldLog('info')) {
        print Term::ANSIColor::colored("[INFO] "  . $_ . "\r\n", 'bright_blue') foreach(split("\r\n", $msg));
    }
}
sub debug {
    my $self = shift;
    my $msg  = shift;
    if($self->shouldLog('debug')) {
        print Term::ANSIColor::colored("[DEBUG] " . $_ . "\r\n", 'bright_cyan') foreach(split("\r\n", $msg));
    }
}

1;
