#!/usr/bin/env perl
use strict;
use warnings;
use inc::Module::Install;

name            'cmpctircd';
author          'sam <sam@cmpct.info>';
version         '0.30';
license         'gpl';
perl_version    '5.020';

all_from 'lib/IRCd/Client.pm';
requires 'IO::Socket::SSL';
requires 'IO::Epoll';
requires 'XML::Simple';
requires 'Term::ANSIColor';
requires 'Net::DNS';
requires 'Datetime';
requires 'Path::Tiny';
requires 'Getopt::Long';
requires 'Module::Install';
requires 'String::Scanf';
requires 'Tie::Refhash';

install_script 'bin/ircd';

postamble <<'END_OF_MAKEFILE';
install:: extra_install
pure_install:: extra_install
install_vendor:: extra_install

extra_install:
	install -d $(DESTDIR)/etc/cmpctircd/
	install -m 640 ircd.xml  $(DESTDIR)/etc/cmpctircd/ircd.xml.example
	install -m 640 ircd.motd $(DESTDIR)/etc/cmpctircd/ircd.motd.example
	install -m 640 ircd.rules $(DESTDIR)/etc/cmpctircd/ircd.rules.example
END_OF_MAKEFILE

WriteAll;


