#!/usr/bin/perl
use strict;
use warnings;
no warnings "experimental::postderef"; # for older perls (<5.24)
use feature 'postderef';
use IRCd::Constants;

package IRCd::Modules::List;

sub new {
    my ($class, %args) = @_;
    my $self  = {
        'name'   => 'IRCd::Modules::List',

        'ircd'   => $args{'ircd'}   // shift,
        'module' => $args{'module'} // shift,
    };
    bless $self, $class;
    $self->{module}->register_module($self);
    return $self;
}


sub pkt_list {
    my $self   = $_[0]->[0];
    my $client = $_[1]->[0];
    my $msg    = $_[2]->[0];

    $client->write(":$client->{ircd}->{host} " . IRCd::Constants::RPL_LISTSTART . " $client->{nick} Channel :Users  Name");
    foreach(values($self->{ircd}->{channels}->%*)) {
        my $chan_name = $_->{name};
        my $chan_size = $_->size();
        my $chan_modes = $_->getModeStrings();
        my $chan_modes_str = $chan_modes->{characters};

        # Only add a space when arguments are present
        if(length($chan_modes->{args}) > 0) {
            $chan_modes_str .= " " . $chan_modes->{args};
        }

        my $chan_topic = $_->{topic}->{text};
        $client->write(":$client->{ircd}->{host} " . IRCd::Constants::RPL_LIST . " $client->{nick} $chan_name $chan_size :[$chan_modes_str] $chan_topic");
    }
    $client->write(":$client->{ircd}->{host} " . IRCd::Constants::RPL_LISTEND   . " $client->{nick} :End of /LIST");
    # We could return -1 to cease processing for this packet (after other events have executed).
    # But there's no reason to do that, so...
    return 1;
}

sub init {
    my $self = shift;
    $self->{module}->register_cmd("LIST", \&pkt_list, $self);
}

1;
