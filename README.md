cmpctircd
=========

About
-----
The aim of this project was to provide a stable, fast, and *modern* ircd.

Status
-----
**This project has been deprecated in favour of [cmpctircd.NET](https://git.cmpct.info/cmpctircd.NET.git).**

**No further development will take place on this project by sam et al.; contact sam if you wish to take over.**
**Anyone wishing to take on the project would be supported by the cmpct collective.**

Testing
-----
Checkout *master*, edit `ircd.xml`, and run `bin/ircd --config ircd.xml --motd ircd.motd --rules ircd.rules` to test.
Windows/others should use `select` as the socket provider  (`<sockets:provider>`). `epoll` is recommended on Linux, with `kqueue` for *BSD.

Use parameter `--loglevel $LEVEL` where `$LEVEL` is one of: `DEBUG, WARN, INFO, ERROR ` to control the logging level. TLS certs and keys should be 'tls\_cert.pem' and 'tls\_key.pem' respectively. Install with `./Makefile.PL; make; (sudo) make install`.

Dependencies
------------
* Net::DNS (libnet-dns-perl, only if `<advanced:dns>` is enabled)
* IO::Socket::SSL (libio-socket-ssl-perl, only if `<server:tls>` is enabled)
* IO::Epoll (libio-epoll-perl, only if `<sockets:provider>` is `epoll`)
* IO::KQueue (N/A, only if `<sockets:provider>` is `kqueue`)
* XML::Simple (libxml-simple-perl)
* Datetime (libdatetime-perl)
* Path::Tiny (libpath-tiny-perl)
* Module::Install (libmodule-install-perl)
* Try::Tiny (libtry-tiny-perl)
* String::Scanf (libstring-scanf-perl)
* Term::ANSIColor (within core on Debian)
* Getopt::Long (within core on Debian)
* Tie::Refhash (within core on Debian)
* `perl >= 5.20` for `postderef`

Branches
--------
*You can use Bugzilla to glean information about the direction of a series.*

* master: stable development, [0.2.x](https://bugs.cmpct.info/buglist.cgi?f1=target_milestone&f2=target_milestone&j_top=AND_G&list_id=770&o1=lessthan&o2=greaterthaneq&order=bug_status%20DESC%2Cchangeddate%20DESC%2Cpriority%2Cassigned_to%2Cbug_id&product=cmpctircd&query_format=advanced&resolution=---&v1=0.3.0&v2=0.2.0) series (bugfixes, small new features)
* next: next major version, [0.3.x](https://bugs.cmpct.info/buglist.cgi?f1=target_milestone&f2=target_milestone&f3=target_milestone&j_top=AND_G&list_id=771&o1=lessthan&o2=greaterthaneq&product=cmpctircd&query_format=advanced&resolution=---&v1=0.4.0&v2=0.3.0) series (link work, etc)

Contact
-------
Email me at sam@cmpct.info if you wish to contribute or you have questions.
