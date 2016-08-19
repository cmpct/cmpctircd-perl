#!/usr/bin/perl
use strict;
use warnings;

package IRCd::Ban;

sub new {
    my ($class, %args) = @_;
    my $self  = {
        'nick'   => $args{nick}   // '*',
        'user'   => $args{user}   // '*',
        'host'   => $args{host}   // '*',
        'setter' => $args{setter} // '*',
        'time'   => $args{time}   // time(),
    };
    bless $self, $class;
    return $self;
}

sub match {
    my $self   = shift;
    my $client = shift;
    my ($nick, $user, $host) = ($self->{nick}, $self->{user}, $self->{host});

    # Substitute * for .*
    $nick =~ s/\*/\.*/;
    $user =~ s/\*/\.*/;
    $host =~ s/\*/\.*/;

    return 0 if($client->{nick}  !~ $nick);
    return 0 if($client->{ident} !~ $user);
    return 0 if($client->{cloak}     !~ $host
                and $client->{host}  !~ $host
                and $client->{ip}    !~ $host);
    return 1;
}

sub mask {
    my $self = shift;
    return $self->{nick} . '!' . $self->{user} . '@' . $self->{host};
}

1;
