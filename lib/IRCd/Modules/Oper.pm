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

    my ($c_name, $c_password, $c_hash, $c_type);
    my $got_match = 0;

    # XXX: Workaround for XML::Simple modifying behaviour basted on number of elements (one oper || many)
    if(!$opers->{$u_name}) {
        $opers->{$u_name} = $ircd->{config}->{opers}->{oper};
    }
    if(my $oper = $opers->{$u_name}) {
        $c_password  = $oper->{password};
        $c_hash      = $oper->{hash} . '_hex';
        $c_type      = $oper->{type} // 'UNIMPLEMENTED';
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
    }
    if(!$got_match) {
        # Incorrect credentials, sorry
        $ircd->{log}->info("User [$client->{nick}] unsuccessfully opered for [$u_name] [type: $c_type]");
        $client->write(":$ircd->{host} " . IRCd::Constants::ERR_NOOPERHOST . " $client->{nick} :Invalid oper credentials");
        return -1;
    } else {
        $ircd->{log}->info("User [$client->{nick}] successfully opered as [$u_name] [type: $c_type]");
    }

    # User is now an oper
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
    my @splitMessage = split(" ", $msg);
    my $u_name       = $splitMessage[1];
    my $u_password   = $splitMessage[2];

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

sub init {
    my $self = shift;
    $self->{module}->register_cmd("OPER",   \&pkt_oper,   $self);
    $self->{module}->register_cmd("SAMODE", \&pkt_samode, $self);
}

1;
