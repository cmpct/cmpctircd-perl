#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;

package IRCd::Sockets::Select;

sub new {
    my $class = shift;
    my $self = {
            select       => IO::Select->new(),
            listenerSock => shift,
    };
    require IO::Select;
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
    my $self   = shift;
    my @result = $self->{select}->can_read(shift);
    return @result;
}

1;
