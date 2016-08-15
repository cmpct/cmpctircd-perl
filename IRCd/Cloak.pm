#!/usr/bin/perl
use strict;
use warnings;
use Digest::MD5;
use String::Scanf;

package IRCd::Cloak;

sub unreal_cloak {
    my $ip                   = shift;
    my ($key1, $key2, $key3) = @_;
    my $buffer               = "";

	# https://github.com/unrealircd/unrealircd/blob/ae0fc98a04fce80e5b940617b9b3f5e43daa2dba/src/modules/cloak.c#L263
	# Output: ALPHA.BETA.GAMMA.IP
	# ALPHA is unique for a.b.c.d
	# BETA  is unique for a.b.c.*
	# GAMMA is unique for a.b.*
	# We cloak like this:
	# ALPHA = downsample(md5(md5("KEY2:A.B.C.D:KEY3")+"KEY1"));
	# BETA  = downsample(md5(md5("KEY3:A.B.C:KEY1")+"KEY2"));
	# GAMMA = downsample(md5(md5("KEY1:A.B:KEY2")+"KEY3"));
    
    # %u => unsigned integer
    my ($alpha, $beta, $gamma);
    my ($a, $b, $c, $d) = String::Scanf::sscanf("%u.%u.%u.%u", $ip);

    ## Alpha ##
    $buffer = "$key2:$ip:$key3";
    $buffer = Digest::MD5::md5($buffer);
    $buffer = Digest::MD5::md5($buffer . $key1);
    $alpha  = IRCd::Cloak::downsample($buffer);

	## Beta ##
    $buffer = "$key3:$a:$b:$c:$key1";
    $buffer = Digest::MD5::md5($buffer);
    $buffer = Digest::MD5::md5($buffer . $key2);
    $beta   = IRCd::Cloak::downsample($buffer);

	## Gamma ##
    $buffer = "$key1:$a:$b:$key2";
    $buffer = Digest::MD5::md5($buffer);
    $buffer = Digest::MD5::md5($buffer . $key3);
    $gamma  = IRCd::Cloak::downsample($buffer);

    # %X => Hex
    return sprintf("%X.%X.%X.IP", $alpha, $beta, $gamma);
}

sub downsample {
    my @buffer = unpack("W*", shift);

    my $r1 = $buffer[0]  ^ $buffer[1]  ^ $buffer[2]  ^ $buffer[3];
    my $r2 = $buffer[4]  ^ $buffer[5]  ^ $buffer[6]  ^ $buffer[7];
    my $r3 = $buffer[8]  ^ $buffer[9]  ^ $buffer[10] ^ $buffer[11];
    my $r4 = $buffer[12] ^ $buffer[13] ^ $buffer[14] ^ $buffer[15];
	
    $r1 = $r1 << 24;
    $r2 = $r2 << 16;
    $r3 = $r3 << 8;
    
    return($r1 + $r2 + $r3 + $r4);
}


1;