#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;

package IRCd::Constants;
# https://www.alien.net.au/irc/irc2numerics.html
# http://www.valinor.sorcery.net/docs/rfc1459/6.1-error-replies.html
# This file interestingly serves as a list of the implemented numerics.
use constant {
    RPL_WELCOME  => '001',
    RPL_YOURHOST => '002',
    RPL_CREATED  => '003',

    RPL_ENDOFWHO      => 315,
    RPL_CHANNELMODEIS => 324,
    RPL_CREATIONTIME  => 329,
    RPL_TOPIC         => 332,
    RPL_WHOREPLY      => 352,
    RPL_NAMREPLY      => 353,
    RPL_ENDOFNAMES    => 366,
    RPL_MOTD          => 372,
    RPL_MOTDSTART     => 375,
    RPL_ENDOFMOTD     => 376,
    # ...
    # Errors
    ERR_NOSUCHNICK     => 401,
    ERR_NOSUCHCHANNEL  => 403,
    ERR_NICKNAMEINUSE  => 433,
    ERR_NOTONCHANNEL   => 442,
    ERR_USERONCHANNEL  => 443,
    ERR_NEEDMOREPARAMS => 461,

};

1;
