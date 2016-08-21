#!/usr/bin/perl
use strict;
use warnings;

package IRCd::Channel::Topic;

sub new {
    my $class = shift;
    my $self  = {
        'text'    => shift // "",
        'channel' => shift,
        'who'     => '',
        'time'    => 0,
    };
    bless $self, $class;
    return $self;
}

sub set {
    my $self     = shift;
    my $client   = shift;
    my $socket   = $client->{socket}->{sock};
    my $config   = $client->{config};
    my $ircd     = $client->{ircd};
    my $mask     = $client->getMask();
    my $topic    = shift;
    my $force    = shift // 0;
    my $announce = shift // 1;

    # XXX: Privilege checks
    # XXX: +t/-t...
    # XXX: RPL_NOTOPIC is more of a JOIN thing?
    return if($self->{text} eq $topic);
    $self->{text} = $topic;
    $self->{who}  = $mask;
    $self->{time} = time();
    if($announce) {
        $self->{channel}->sendToRoom($client, ":$mask TOPIC $self->{channel}->{name} :$topic");
    }
}
sub get {
    my $self = shift;
    return $self->{text};
}

sub metadata {
    my $self = shift;
    return {
      'text'    => $self->{text},
      'channel' => $self->{channel},
      'who'     => $self->{who},
      'time'    => $self->{time}
    };
}

1;
