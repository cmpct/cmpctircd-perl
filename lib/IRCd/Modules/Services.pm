#!/usr/bin/perl
use strict;
use warnings;
no warnings "experimental::postderef"; # for older perls (<5.24)
use feature 'postderef';
use IRCd::Constants;

package IRCd::Modules::Services;

sub new {
    my ($class, %args) = @_;
    my $self  = {
        'name'   => 'IRCd::Modules::Services',
        'ircd'   => $args{'ircd'}   // shift,
        'module' => $args{'module'} // shift,
    };
    bless $self, $class;
    $self->{module}->register_module($self);
    return $self;
}


sub pkt_sjoin {
    my $self   = $_[0]->[0];
    my $srv    = $_[1]->[0];
    my $msg    = $_[1]->[1];
    my $ircd   = $self->{ircd};
    my $client;

    if(ref($srv) eq 'IRCd::Client') {
        # No users (clients) allowed! Servers only.
        # Could also check by looking at if ->{server} eq ->{ircd}->{host}
        return -1;
    }
    my @splitPacket = split(" ", $msg, 5);
    my $timestamp    = $splitPacket[2];
    my $channelInput = $splitPacket[3];

    @splitPacket = split(":", $msg, 3);
    my @users    = split(" ", $splitPacket[2]);

    # [DEBUG][SERVER] RECV: :00A SJOIN 1473258753 #services + :@00AAAAAAI;
    foreach(@users) {
        $_      =~ s/@//;
        $client = $srv->{clients}->{uid}->{$_};

        if($ircd->{channels}->{$channelInput}) {
            $ircd->{channels}->{$channelInput}->addClient($client);
        } else {
            $client->{log}->info("[$channelInput] Creating channel..");
            my $channel = IRCd::Channel->new($channelInput);
            $channel->initModes($client, $ircd);
            $channel->addClient($client);
            $ircd->{channels}->{$channelInput} = $channel;
        }
    }
    #$ircd->{log}->info("Remote user $client->{nick} joining");
    return 1;
}

sub evt_sjoin {
    my $self   = $_[0]->[0];
    my $client = $_[1]->[0];
    my $chan   = $_[1]->[1];
    my $ircd   = $self->{ircd};
    my $srv;

    # https://www.unrealircd.org/files/docs/technical/serverprotocol.html#S5_1
    $ircd->{log}->info("$client->{nick} finished joining $chan->{name}");
    foreach(keys($ircd->{servers}->{sid}->%*)) {
        # Push the SJOIN to all the servers
        # :001 SJOIN 1473257992 #services :@001YIMH01
        $srv = $ircd->{servers}->{sid}->{$_};
        next if(!$srv->{socket}->{sock});
        $srv->write(":$ircd->{sid} SJOIN " . time() . " $chan->{name} :\@$client->{nick}");
    }

    return 1;
}


sub init {
    my $self = shift;
    $self->{module}->register_cmd("SJOIN", \&pkt_sjoin, $self);
    $self->{module}->register_event("channel_join_done", \&evt_join, $self);
}

1;
