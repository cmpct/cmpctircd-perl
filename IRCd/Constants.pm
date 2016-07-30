#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;

package IRCd::Constants;

our %errors = {
    'RPL_WELCOME'  => 001,
    'RPL_YOURHOST' => 002,
    'RPL_CREATED'  => 003,
    # ...
    # Errors
    'ERR_NEEDMOREPARAMS' => 461,
}

1;
