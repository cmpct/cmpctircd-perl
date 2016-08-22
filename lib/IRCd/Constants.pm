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
    RPL_MYINFO   => '004',
    RPL_ISUPPORT => '005',

    RPL_AWAY          => 301,
    RPL_UNAWAY        => 305,
    RPL_NOWAWAY       => 306,

    RPL_WHOISUSER     => 311,
    RPL_WHOISSERVER   => 312,
    RPL_WHOISOPERATOR => 313,
    RPL_WHOISIDLE     => 317,
    RPL_ENDOFWHOIS    => 318,
    RPL_WHOISCHANNELS => 319,

    RPL_ENDOFWHO      => 315,
    RPL_CHANNELMODEIS => 324,
    RPL_CREATIONTIME  => 329,
    RPL_NOTOPIC       => 331,
    RPL_TOPIC         => 332,
    RPL_TOPICWHOTIME  => 333,
    RPL_WHOREPLY      => 352,
    RPL_NAMREPLY      => 353,
    RPL_ENDOFNAMES    => 366,
    RPL_BANLIST       => 367,
    RPL_ENDOFBANLIST  => 368,
    RPL_MOTD          => 372,
    RPL_MOTDSTART     => 375,
    RPL_ENDOFMOTD     => 376,
    RPL_WHOISHOST     => 378,
    RPL_HOSTHIDDEN    => 396,
    RPL_WHOISSECURE   => 671,

    # Errors
    ERR_NOSUCHNICK       => 401,
    ERR_NOSUCHCHANNEL    => 403,
    ERR_CANNOTSENDTOCHAN => 404,
    ERR_ERRONEUSNICKNAME => 432,
    ERR_NICKNAMEINUSE    => 433,
    ERR_USERNOTINCHANNEL => 441,
    ERR_NOTONCHANNEL     => 442,
    ERR_USERONCHANNEL    => 443,
    ERR_NOTREGISTERED    => 451,
    ERR_NEEDMOREPARAMS   => 461,
    ERR_CHANNELISFULL    => 471,
    ERR_BANNEDFROMCHAN   => 474,
    ERR_CHANOPRIVSNEEDED => 482,
};

1;
