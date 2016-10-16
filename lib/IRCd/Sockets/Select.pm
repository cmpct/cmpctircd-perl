#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;

package IRCd::Sockets::Select;

sub new {
    my $class = shift;
    require IO::Select;
    my $self = {
            select       => IO::Select->new(),
            listenerSock => shift,
            log          => shift,
    };
    bless $self, $class;
    $self->add($self->{listenerSock});
    return $self;
}

sub add {
    my $self = shift;
    foreach(@_) {
        $self->{select}->add($_);
    }
}
sub del {
    my $self = shift;
    foreach(@_) {
        $self->{select}->remove($_);
    }
}

sub readable {
    my $self    = shift;
    my $timeout = shift;

    # We don't want to ever block, but IO::Select/Epoll do not have the same
    # behaviour as others. Some assume 0 = block, others assume 0 = immediate return.
    # Therefore, we always set a (very low) timeout if $timeout <= 0.
    # http://perldoc.perl.org/IO/Select.html#METHODS
    $timeout = 0.1 if $timeout <= 0;

    my @result = $self->{select}->can_read($timeout);
    return @result;
}

1;
