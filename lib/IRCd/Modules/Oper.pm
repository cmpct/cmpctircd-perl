#!/usr/bin/perl
use strict;
use warnings;
use IRCd::Constants;
use Digest::SHA;

package IRCd::Modules::Oper;

sub new {
    my ($class, %args) = @_;
    my $self  = {
        'name'   => 'IRCd::Modules::Oper',
        'ircd'   => $args{'ircd'}   // shift,
        'module' => $args{'module'} // shift,
    };
    bless $self, $class;
    $self->{module}->register_module($self);
    return $self;
}

sub pkt_oper {
    my $self         = $_[0]->[0];
    my $client       = $_[1]->[0];
    my $msg          = $_[1]->[1];
    my $ircd         = $client->{ircd};
    my $opers        = $ircd->{config}->{opers}->{oper};
    my @splitMessage = split(" ", $msg);
    my $u_name       = $splitMessage[1];
    my $u_password   = $splitMessage[2];

    my ($c_name, $c_password, $c_hash, $c_type, $c_tls, $c_host);
    my $got_match  = 0;

    # XXX: Workaround for XML::Simple modifying behaviour based on number of elements (one oper || many)
    if(!$opers->{$u_name}) {
        $opers->{$u_name} = $ircd->{config}->{opers}->{oper};
    }
    if(my $oper = $opers->{$u_name}) {
        $c_password  = $oper->{password};
        $c_hash      = $oper->{hash} . '_hex';
        $c_type      = $oper->{type} // 'UNIMPLEMENTED';
        $c_tls       = $oper->{tls}  // 0;
        $c_host      = $oper->{host} // '*';
        $ircd->{log}->debug("[$client->{nick}] Found ircop $u_name [$c_type]");
        # XXX: Support something other than SHA*
        if(my $hash_ref = Digest::SHA->can($c_hash)) {
            $ircd->{log}->debug("[$client->{nick}] Attempting auth using $c_hash");
            if($hash_ref->($u_password) eq $c_password) {
                $got_match = 1;
            }
        } else {
            $ircd->{log}->warn("[$client->{nick}] No such hash function as $c_hash! EDIT YOUR CONFIG FILE.");
        }

        # Does the <oper> block require TLS (and is the user connected via TLS)?
        if($c_tls and !$client->{modes}->{z}->has($client)) {
            $ircd->{log}->warn("[$client->{nick}] User tried to authenicate as $u_name [$c_type] [tls: $c_tls] without using TLS!");
            $got_match = 0;
        }
        # Does the <oper> block provide a host for $client to match?
        if($c_host) {
            # Host looks like 'user@host'
            my @u_host = split('@', $c_host);
            my $u_user = lc($u_host[0]) // '*';
            my $u_host = lc($u_host[1]) // '*';
            $u_user =~ s/\*/\.*/;
            $u_host =~ s/\*/\.*/;

            # We don't tell the user any specific reason for the lack of success
            # This is a security feature
            if($client->{ident} =~ $u_user and $client->{host} =~ $u_host) {
                $ircd->{log}->info("User [$client->{nick}] matches $u_user\@$u_host");
            } else {
                $ircd->{log}->info("User [$client->{nick}] Host tuplet ($client->{ident}\@$client->{host}) DOESN'T match regex ($u_user\@$u_host)");
                $got_match  = 0;
            }
        }
    }
    if(!$got_match) {
        # Incorrect credentials, sorry
        $ircd->{log}->info("User [$client->{nick}] unsuccessfully opered for [$u_name] [type: $c_type]");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_NOOPERHOST . " $client->{nick} :Invalid oper credentials");
        return -1;
    }

    # User is now an oper
    $ircd->{log}->info("User [$client->{nick}] successfully opered as [$u_name] [type: $c_type]");
    # Set the appropriate modes
    $client->{modes}->{o}->grant('+', 'o', undef, 1, 1);
    # Tell them
    $client->write(":$ircd->{host} " . IRCd::Constants::RPL_YOUREOPER . " $client->{nick} :You are now an IRC operator");

    # We could return -1 to cease processing for this packet (after other events have executed).
    # But there's no reason to do that, so...
    return 1;
}

sub pkt_samode {
    my $self         = $_[0]->[0];
    my $client       = $_[1]->[0];
    my $msg          = $_[1]->[1];
    my $ircd         = $client->{ircd};
    my $opers        = $ircd->{config}->{opers}->{oper};

    if(!$client->{modes}->{o}->has($client)) {
        $client->{log}->warn("[$client->{nick}] User attempted to use SAMODE ($msg) when not an ircop!");
        return -1;
    }
    $client->{log}->info("[$client->{nick}] User used SAMODE ($msg)");
    IRCd::Client::Packets::mode($client, $msg, 1);
    # We could return -1 to cease processing for this packet (after other events have executed).
    # But there's no reason to do that, so...
    return 1;
}

sub pkt_satopic {
    my $self         = $_[0]->[0];
    my $client       = $_[1]->[0];
    my $msg          = $_[1]->[1];
    my $ircd         = $client->{ircd};
    my $opers        = $ircd->{config}->{opers}->{oper};

    if(!$client->{modes}->{o}->has($client)) {
        $client->{log}->warn("[$client->{nick}] User attempted to use SATOPIC ($msg) when not an ircop!");
        return -1;
    }
    $client->{log}->info("[$client->{nick}] User used SATOPIC ($msg)");
    IRCd::Client::Packets::topic($client, $msg, 1);
    # We could return -1 to cease processing for this packet (after other events have executed).
    # But there's no reason to do that, so...
    return 1;
}

sub init {
    my $self = shift;
    $self->{module}->register_cmd("OPER",    \&pkt_oper,    $self);
    $self->{module}->register_cmd("SAMODE",  \&pkt_samode,  $self);
    $self->{module}->register_cmd("SATOPIC", \&pkt_satopic, $self);
}

1;
