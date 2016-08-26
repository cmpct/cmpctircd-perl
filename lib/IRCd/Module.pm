#!/usr/bin/perl
use strict;
use warnings;
use Carp;
use Tie::RefHash;
package IRCd::Module;

# IRCd::Module provides two methods of 'events':
# 1) 'command' events, which are their own way of registering received commands;
# 2) generic events, such as handle_user_pong which provide a way of hooking into
# more specific behaviour.
sub new {
    my $class = shift;
    my $self  = {
        'ircd'     => shift,
        'modules'  => {},
        'handlers' => {},
        'events'   => {},
    };
    bless $self, $class;
    return $self;
}

# Command codes
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
    my $returnValues = {};
    # Execute all registered handlers for $packet
    foreach(@handlers) {
        my $ref  = $_;
        my $args = $self->{handlers}->{$packet}->{$_};
        $returnValues->{$ref} = $_->($args, $userArgs);
        $found = 1;
    }
    # returns if we found a handler or not (for ERR_UNKNOWNCOMMAND)
    return {
        'values' => $returnValues,
        'found'  => $found,
    };
}

#               #
#    Modules    #
#               #
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

#              #
#    Events    #
#              #
sub register_event {
    my $self    = shift;
    my $event   = lc(shift);
    my $ref     = shift;
    my $args    = \@_;
    # Needed to use refs as a hash key
    if(!$self->{events}->{$event}) {
        tie $self->{events}->{$event}->%*, 'Tie::RefHash';
    }
    $self->{events}->{$event}->{$ref} = $args;
}
sub unregister_event {
    my $self     = shift;
    my $event    = lc(shift);
    my $ref      = shift;
    delete $self->{events}->{$event}->{$ref};
}

sub fire_event {
    my $self     = shift;
    my $event    = lc(shift);
    my @handlers = keys($self->{events}->{$event}->%*);
    my $userArgs = \@_;
    my $found    = 0;
    my %returnValues = {};
    # Execute all registered handlers for $event
    # Keep a list of all of the return values
    foreach(@handlers) {
        my $ref  = $_;
        my $args = $self->{events}->{$event}->{$_};
        $returnValues{$ref} = $_->($args, $userArgs);
        $found = 1;
    }
    # returns if we found a handler or not
    return {
        'values' => $returnValues,
        'found'  => $found,
    };
}

#             #
#  Utilities  #
#             #
sub can_process {
    # Events can signal the ircd core to 'stop processing' the current command
    # ...by returning a value < 0 (e.g. -1).
    # This function checks if any of the events sent that signal.
    # Returns 1 if ok to continue, 0 if not.
    my $returnValues = shift;
    foreach(values($returnValues->%*)) {
        return 0 if($_ < 0);
    }
    return 1;
}

1;
