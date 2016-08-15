cmpctircd
=========

About
-----
The aim of this project is to provide a stable, fast, and *modern* ircd.

Status
-----
For now, it is still under heavy development. It will be clear when it is production ready. 
[Bugzilla](https://bugs.cmpct.info/) is a good indicator of progress.

Checkout *master*, edit `ircd.xml`, and run `./ircd.pl` to test.
Windows is untested as of yet, but it should run with `select` as the socket provider  (`<sockets:provider>`). `epoll` is 
recommended on Linux.

Dependencies
------------
* IO::Epoll (libxml-simple-perl)
* XML::Simple  (libio-epoll-perl)
* Term::ANSIColor (within core on Debian)
* Net::DNS (libnet-dns-perl)
* String::Scanf (install with CPAN)
* `perl >= 5.20` for `postderef`

Contact
-------
Email me at sam@cmpct.info if you wish to contribute or you have questions.
An IRC server will be created once *cmpctircd* is ready to self-host -- **soon**.
