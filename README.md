cmpctircd
=========

About
-----
The aim of this project is to provide a stable, fast, and *modern* ircd.

Status
-----
For now, it is still under heavy development. It will be clear when it is production ready. 
[Bugzilla](https://bugs.cmpct.info/) is a good indicator of progress.

Checkout *master*, edit `ircd.xml`, and run `bin/ircd --config ircd.xml --motd ircd.motd --rules ircd.rules` to test.
Windows is untested as of yet, but it should run with `select` as the socket provider  (`<sockets:provider>`). `epoll` is 
recommended on Linux.

TLS certs and keys should be 'tls\_cert.pem' and 'tls\_key.pem' respectively. Install with `./Makefile.PL; make; sudo make
install`.

Dependencies
------------
* IO::Socket::SSL (libio-socket-ssl-perl, only if `<server:tls>` is enabled)
* IO::Epoll (libio-epoll-perl)
* XML::Simple (libxml-simple-perl)
* Term::ANSIColor (within core on Debian)
* Net::DNS (libnet-dns-perl)
* Getopt::Long (within core on Debian)
* Datetime (libdatetime-perl)
* Path::Tiny (libpath-tiny-perl)
* Module::Install (libmodule-install-perl)
* String::Scanf (install with CPAN)
* `perl >= 5.20` for `postderef`

Contact
-------
Email me at sam@cmpct.info if you wish to contribute or you have questions.
An IRC server will be created once *cmpctircd* is ready to self-host -- **soon**.
