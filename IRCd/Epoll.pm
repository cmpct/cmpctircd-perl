#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
use IO::Epoll;

package IRCd::Epoll;

sub new {
    my $class = shift;
    my $self = {
            epoll => IO::Epoll::epoll_create(10),
            sockets => {},
            listenerSock => shift,
    };
    bless $self, $class;
    $self->addSock($self->{listenerSock});
    return $self;
}

sub addSock {
    my $self = shift;
    foreach(@_) {
        IO::Epoll::epoll_ctl($self->{epoll}, IO::Epoll::EPOLL_CTL_ADD(), fileno($_), IO::Epoll::EPOLLIN());
    }
}
sub delSock {
    my $self = shift;
    foreach(@_) {
        IO::Epoll::epoll_ctl($self->{epoll}, IO::Epoll::EPOLL_CTL_DEL(), fileno($_), 1);
    }
}

sub removeSock {
    my $self =  shift;
    foreach(@_) {
        IO::Epoll::epoll_ctl($self->{epoll}, IO::Epoll::EPOLL_CTL_DEL(), fileno($_), 1);
    }
}
sub getReadable {
    my $self = shift;
    my $result = IO::Epoll::epoll_wait($self->{epoll}, 1024, shift);
    return $result;
}

1;
