#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
use IO::Epoll;

package IRCd::Sockets::Epoll;

sub new {
    my $class = shift;
    require IO::Epoll;
    my $self = {
            epoll        => IO::Epoll::epoll_create(10),
            listenerSock => shift,
    };
    bless $self, $class;
    $self->add($self->{listenerSock});
    return $self;
}
sub add {
    my $self = shift;
    foreach(@_) {
        IO::Epoll::epoll_ctl($self->{epoll}, IO::Epoll::EPOLL_CTL_ADD(), fileno($_), IO::Epoll::EPOLLIN());
    }
}
sub del {
    my $self = shift;
    foreach(@_) {
        IO::Epoll::epoll_ctl($self->{epoll}, IO::Epoll::EPOLL_CTL_DEL(), fileno($_), 1);
    }
}
sub readable {
    my $self = shift;
    my $result = IO::Epoll::epoll_wait($self->{epoll}, 1024, shift);
    return @$result;
}

1;
