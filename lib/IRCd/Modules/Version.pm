#!/usr/bin/perl
use strict;
use warnings;
use IRCd::Constants;

package IRCd::Modules::Version;

sub new {
    my ($class, %args) = @_;
    my $self  = {
        'name'   => 'IRCd::Modules::Version',
        'ircd'   => $args{'ircd'}   // shift,
        'module' => $args{'module'} // shift,
    };
    bless $self, $class;
    $self->{module}->register_module($self);
    return $self;
}


sub pkt_version {
    my $self   = $_[0]->[0];
    my $client = $_[1]->[0];
    my $msg    = $_[2]->[0];

    # Print git HEAD if we can
    if(-e '/usr/bin/git') {
        my $HEAD = `git rev-parse HEAD`;
        $HEAD    =~ s/\r?\n//;
        $client->write(":$client->{ircd}->{host} " . IRCd::Constants::RPL_VERSION . " $client->{nick} cmpctircd-$self->{ircd}->{version}-$HEAD");
    } else {
        $client->write(":$client->{ircd}->{host} " . IRCd::Constants::RPL_VERSION . " $client->{nick} cmpctircd-$self->{ircd}->{version}");
    }
    # We could return -1 to cease processing for this packet (after other events have executed).
    # But there's no reason to do that, so...
    return 1;
}

sub init {
    my $self = shift;
    $self->{module}->register_cmd("VERSION", \&pkt_version, $self);
}

1;
