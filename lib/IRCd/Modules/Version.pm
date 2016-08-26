#!/usr/bin/perl
use strict;
use warnings;
use IRCd::Constants;

package IRCd::Modules::Version;

sub new {
    my ($class, %args) = @_;
    my $self  = {
        'name'   => 'IRCd::Version',

        'ircd'   => $args{'ircd'}   // shift,
        'module' => $args{'module'} // shift,
        'count'  => $args{'count'}  // 0,
    };
    bless $self, $class;
    $self->{module}->register_module($self);
    return $self;
}


sub pkt_version {
    my $self   = $_[0]->[0];
    my $client = $_[1]->[0];
    my $msg    = $_[2]->[0];
    # Demonstrate state
    $self->{count}++;
    $client->write(":$client->{ircd}->{host} NOTICE $client->{nick} :The command VERSION has been called $self->{count} times.");

    # Print git HEAD if we can
    if(-e '/usr/bin/git') {
        my $HEAD = `git rev-parse HEAD`;
        $HEAD    =~ s/\r?\n//;
        $client->write(":$client->{ircd}->{host} " . IRCd::Constants::RPL_VERSION . " $client->{nick} cmpctircd-$self->{ircd}->{version}-$HEAD");
    } else {
        $client->write(":$client->{ircd}->{host} " . IRCd::Constants::RPL_VERSION . " $client->{nick} cmpctircd-$self->{ircd}->{version}");
    }
}


sub init {
    my $self = shift;
    $self->{module}->register_cmd("VERSION", \&pkt_version, $self);
}

1;
