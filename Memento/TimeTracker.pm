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
  my $commands = Memento::Tool->commands();
  my $time_trackers = [];

  foreach my $command (keys %{$commands}) {
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

sub _get_api_id_names {
  my $class = shift;
  my $config = $class->_get_config();
  my @api_id_names;

  foreach my $api (@{$config->{api}}) {
    push(@api_id_names, $api->{id});
  }
  return [@api_id_names];
}

sub _get_current_api_id {
  my $class = shift;
  my $config = $class->_get_config();
  my $git = Memento::Tool->instantiate('git');
  my $git_config = $git->_get_config(1);
  return $git_config->{time_tracker_id} ? $git_config->{time_tracker_id} : $config->{default};
}

1;
