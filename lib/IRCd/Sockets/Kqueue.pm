#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
no warnings "experimental::postderef"; # for older perls (<5.24)
use feature 'postderef';

package IRCd::Sockets::Kqueue;

sub new {
    my $class = shift;
    require IO::KQueue;
    my $self = {
            kqueue       => IO::KQueue->new(),
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
        $self->{kqueue}->EV_SET(fileno($_), IO::KQueue::EVFILT_READ(), IO::KQueue::EV_ADD(), 0, 5);
    }
}
sub del {
    my $self = shift;
    foreach(@_) {
        $self->{kqueue}->EV_SET(fileno($_), IO::KQueue::EVFILT_READ(), IO::KQueue::EV_DELETE(), 0, 5);
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
    my @result = $self->{kqueue}->kevent($timeout);

    my @fds    = ();
    foreach(@result) {
       push @fds, $_->[IO::KQueue::KQ_IDENT()];
    }
    # http://cpansearch.perl.org/src/MSERGEANT/IO-KQueue-0.34/KQueue.pm
    # "Returns nothing. Throws an exception on failure."
    # It's not clear what that means for Perl error handling...
    # XXX: Implement error handling if sense can be made of IO::KQueue.
    #if(!@result) {
    #    $self->{ircd}->{log}->error("kevent returned undef. errno: $!");
    #    return ();
    #}
    return @fds;
}

1;
