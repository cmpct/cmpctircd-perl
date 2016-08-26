#!/usr/bin/perl
use strict;
use warnings;
use Carp;
use Tie::RefHash;
package IRCd::Module;

sub new {
    my $class = shift;
    my $self  = {
        'ircd'     => shift,
        'modules'  => {},
        'handlers' => {},
    };
    bless $self, $class;
    return $self;
}

sub register_cmd {
    my $self    = shift;
    my $packet  = uc(shift);
    my $ref     = shift;
    my $args    = \@_;

    # Needed to use refs as a hash key
    if(!$self->{handlers}->{$packet}) {
        tie $self->{handlers}->{$packet}->%*, 'Tie::RefHash';
    }
    $self->{handlers}->{$packet}->{$ref} = $args;
}
sub unregister_cmd {
    my $self     = shift;
    my $packet   = uc(shift);
    my $ref      = shift;
    delete $self->{handlers}->{$packet}->{$ref};
}

sub exec {
    my $self     = shift;
    my $packet   = uc(shift);
    my @handlers = keys($self->{handlers}->{$packet}->%*);
    my $userArgs = \@_;
    my $found    = 0;
    # Execute all registered handlers for $packet
    foreach(@handlers) {
        my $ref  = $_;
        my $args = $self->{handlers}->{$packet}->{$_};
        $_->($args, $userArgs);
        $found = 1;
    }
    # returns if we found a handler or not (for ERR_UNKNOWNCOMMAND)
    return $found;
}

sub register_module {
    my $self          = shift;
    my $module_object = shift;
    my $module        = ref($module_object);
    if($self->{modules}->{$module}) {
        Carp::croak "A module of name $module already exists.";
        return 0;
    }
    $self->{modules}->{$module_object} = $module;
}
sub unregister_module {
    my $self          = shift;
    my $module_object = shift;
    my $module        = ref($module_object);
    if(!$self->{modules}->{$module}) {
        Carp::croak "No module named $module is registered.";
        return 0;
    }
    delete $self->{modules}->{$module};
}
sub is_loaded_module {
    my $self   = shift;
    my $module = shift;
    return 1 if($self->{modules}->{$module});
    return 0;
}

1;
