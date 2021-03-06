#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Memento/Command.pm";

package Memento::IssueTracker;

our @ISA = qw(Memento::Command);
use strict; use warnings;
use Class::ISA;
use feature 'say';

sub new {
  my ($class, @args) = @_;
  my $instance = $class->SUPER::new(@args);
  $instance->check_interface__IssueTracker;
  $instance;
}

sub check_interface__IssueTracker {
  my ($self) = @_;
  my $errors = 0;
  my @methods = (
    'config',
    'issue',
    '_change_issue_status',
    '_get_issue',
    '_render_issue',
    '_call_api',
    '_name',
    '_branch_pattern',
    '_time_tracker_entry'
  );
  foreach my $method (@methods) {
    if (!$self->can($method)) {
      say "[IssueTracker] - missing '$method()' implementation.";
      $errors++;
    }
  }

  if ($errors > 0) {
    my $ref = ref $self;
    die "[Tool] '$ref' does not implement all IssueTracker required methods.\n";
  }
}

sub _get_all {
  my $commands = Memento::Tool->commands();
  my $issue_trackers = [];

  foreach my $command (keys %{$commands}) {
    my $tool = Memento::Tool->instantiate($command);
    my @classes = Class::ISA::super_path(ref $tool);
    if (Daemon::in_array([@classes], 'Memento::IssueTracker')) {
      push(@{$issue_trackers}, $command);
    }
  }

  return $issue_trackers;
}

sub _is_default {
  my $class = shift;
  my $git = Memento::Tool->instantiate('git');
  my $git_config = $git->_get_config();

  return ($git_config->{issue_tracker} eq $class->_name());
}

sub _fix_branch_prefix {
  my $class = shift;
  my $prefix = shift;
  my $issue = shift;
  return $prefix;
}

sub _fix_branch_name {
  my $class = shift;
  my $branch = shift;
  my $issue = shift;
  return $branch;
}

sub _get_api_ids {
  my $class = shift;
  my $config = $class->_get_config();
  my $api_ids;
  my $i = 0;

  foreach my $api (@{$config->{api}}) {
    $api_ids->{$api->{id}} = $i;
    $i++;
  }
  return $api_ids;
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
  return $git_config->{issue_tracker_id} ? $git_config->{issue_tracker_id} : $config->{default};
}

1;
