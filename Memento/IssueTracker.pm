#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Memento/Command.pm";

package Memento::IssueTracker;

our @ISA = qw(Memento::Command);
use strict; use warnings;
use Class::ISA;
use Data::Dumper;
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
    'issue',
    '_change_issue_status',
    '_get_issue',
    '_render_issue',
    '_call_api'
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
  my @commands = Memento::Tool->commands();
  my $issue_trackers = [];

  foreach my $command (@commands) {
    my $tool = Memento::Tool->instantiate($command);
    my @classes = Class::ISA::super_path(ref $tool);
    if (Daemon::in_array([@classes], 'Memento::IssueTracker')) {
      push(@{$issue_trackers}, $command);
    }
  }

  return $issue_trackers;
}

1;
