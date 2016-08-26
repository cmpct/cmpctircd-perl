#!/usr/bin/perl
use strict;
use warnings;
no warnings "experimental::postderef"; # for older perls (<5.24)
use feature 'postderef';

use IRCd::Constants;

package IRCd::Modes::User::TLS;

sub new {
    my $class = shift;
    my $self  = {
        'name'     => 'tls',
        'provides' => 'z',
        'desc'     => 'User is using a secure connection.',
        'affects'  => {},
        'client'   => shift,

        'hasparam' => 0,
    };
    bless $self, $class;
    return $self;
}

sub grant {
    my $self     = shift;
    my $client   = $self->{client};
    my $socket   = $client->{socket}->{sock};
    my $config   = $client->{config};
    my $ircd     = $client->{ircd};
    my $modifier = shift // "+";
    my $mode     = shift // "z";
    my $args     = shift // "";
    my $force    = shift // 0;
    my $announce = shift // 1;
    my $targetClient = undef;
    my $mask = $client->getMask(1);

    return if (!$force and !$client->{tls});
    $self->{client}->{log}->debug("[$client->{nick}] setting +z");
    $self->{client}->write(":$mask MODE $client->{nick} $modifier$mode $args") if $announce;
    $self->{affects}->{$client} = 1;

}
sub revoke {
    my $self     = shift;
    my $client   = $self->{client};
    my $socket   = $client->{socket}->{sock};
    my $config   = $client->{config};
    my $ircd     = $client->{ircd};
    my $modifier = shift // "-";
    my $mode     = shift // "z";
    my $args     = shift // $client->{nick};
    my $force    = shift // 0;
    my $announce = shift // 1;
    my $targetClient = undef;
    my $mask = $client->getMask(0);

    return if(!$force);
    $self->{client}->{log}->debug("[$client->{nick}] unsetting +z");
    $self->{client}->write(":$mask MODE $client->{nick} $modifier$mode $args") if $announce;
    delete $self->{affects}->{$client};
}
sub get {
    my $self = shift;
    return 1 if($self->has($self->{client}));
    return 0;
}
sub has {
    my $self   = shift;
    my $client = shift;
    return 1 if($self->{affects}->{$client});
    return 0;
}
sub level {
    # 0 => normal
    # 1 => voice
    # 2 => halfop
    # 3 => op
    # 4 => admin
    # 5 => owner
    return 0;
}
sub symbol {
    return 'N/A';
}

1;
