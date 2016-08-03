#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Memento/Command.pm";

package Memento::TimeTracker;

our @ISA = qw(Memento::Command);
use strict; use warnings;
use Class::ISA;
use feature 'say';

sub new {
  my ($class, @args) = @_;
  my $instance = $class->SUPER::new(@args);
  $instance->check_interface__TimeTracker;
  $instance;
}

sub check_interface__TimeTracker {
  my ($self) = @_;
  my $errors = 0;
  my @methods = (
    'config',
    '_call_api',
    '_name'
  );
  foreach my $method (@methods) {
    if (!$self->can($method)) {
      say "[TimeTracker] - missing '$method()' implementation.";
      $errors++;
    }
  }

  if ($errors > 0) {
    my $ref = ref $self;
    die "[Tool] '$ref' does not implement all TimeTracker required methods.\n";
  }
}

sub _get_all {
  my @commands = Memento::Tool->commands();
  my $time_trackers = [];

  foreach my $command (@commands) {
    my $tool = Memento::Tool->instantiate($command);
    my @classes = Class::ISA::super_path(ref $tool);
    if (Daemon::in_array([@classes], 'Memento::TimeTracker')) {
      push(@{$time_trackers}, $command);
    }
  }

  return $time_trackers;
}

sub _is_default {
  my $class = shift;
  my $git = Memento::Tool->instantiate('git');
  my $git_config = $git->_get_config();

  return ($git_config->{time_tracker} eq $class->_name());
}

1;
