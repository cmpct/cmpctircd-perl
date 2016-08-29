#!/usr/bin/perl
use strict;
use warnings;
no warnings "experimental::postderef"; # for older perls (<5.24)
use feature 'postderef';
use XML::Simple;

use IRCd::Sockets::Epoll;
use IRCd::Sockets::Select;
use IRCd::Module;

package IRCd::Config;

sub new {
    my $class = shift;
    my $self = {
        'filename' => shift,
        # <ircd>
        'host'     => undef,
        'network'  => undef,
        'desc'     => undef,
        # <server>
        'ip'       => undef,
        'port'     => undef,
        # <sockets>
        'provider' => undef,
        # <advanced>
        'requirepong' => undef,
        'pingtimeout' => undef,
        'maxtargets'  => undef,
    };
    bless $self, $class;
    return $self;
}

sub parse {
    my $self   = shift;
    my $parse  = XML::Simple->new(
        KeyAttr => {
            mode => 'name',
            oper => 'name',
        },
    );
    my $xmlRef = $parse->XMLin("ircd.xml");

    $self->{ip}             = $xmlRef->{'server'}->{'ip'};
    $self->{port}           = $xmlRef->{'server'}->{'port'};
    $self->{tls}            = $xmlRef->{'server'}->{'tls'};
    $self->{tlsport}        = $xmlRef->{'server'}->{'tlsport'};
    $self->{host}           = $xmlRef->{'ircd'}->{'host'};
    $self->{network}        = $xmlRef->{'ircd'}->{'network'};
    $self->{desc}           = $xmlRef->{'ircd'}->{'desc'};
    $self->{channelmodes}   = $xmlRef->{'channelmodes'};
    $self->{usermodes}      = $xmlRef->{'usermodes'};
    $self->{cloak_keys}     = $xmlRef->{'cloak'}->{'key'};
    $self->{hidden_host}    = $xmlRef->{'cloak'}->{'hiddenhost'};
    $self->{socketprovider} = $xmlRef->{'sockets'}->{'provider'};
    $self->{log}            = $xmlRef->{'log'};
    $self->{requirepong}    = $xmlRef->{'advanced'}->{'requirepong'};
    $self->{dns}            = $xmlRef->{'advanced'}->{'dns'};
    $self->{pingtimeout}    = $xmlRef->{'advanced'}->{'pingtimeout'};
    $self->{maxtargets}     = $xmlRef->{'advanced'}->{'maxtargets'};
    $self->{opers}          = $xmlRef->{'opers'};
}

sub getSockProvider {
    my $self     = shift;
    my $listener = shift;
    # Honour their preference until we can't.
    my $OS = $^O;
    return IRCd::Sockets::Epoll->new($listener)  if($self->{socketprovider} eq "epoll" and $OS eq 'linux');
    return IRCd::Sockets::Select->new($listener) if($self->{socketprovider} eq "select");
}

sub setupHandlers {
    my $self  = shift;
    my $ircd  = shift;
    my $path  = shift;

    $self->{module} = IRCd::Module->new;
    opendir (DIR, $path) or die $!;
    while (my $file = readdir(DIR)) {
        # return if the file ends with a '.'
        # return if the file doesn't end with '.pm'
        # instantiate the module
        # execute its hook setup (->init())
        next    if ($file    =~ m/^\./);
        next    unless($file =~ m/.pm$/);
        require $path . '/' . $file;
        $file =~ s/.pm//;
        $file = 'IRCd::Modules::' . $file;
        $file->new(
            'ircd'   => $ircd,
            'module' => $self->{module},
        )->init();
    }
    closedir(DIR);
}

1;
