#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Memento/Command.pm";

package Memento::Tool::activity;

use feature 'say';
our @ISA = qw(Memento::Command);
use strict; use warnings;
use Encode qw(decode);
use Cwd;
use Getopt::Long;
use Switch;
use Text::Trim;
use Data::Dumper;

sub config {
  my $class = shift;
  my $op = shift;

  if (!$op) {
    $op = Daemon::prompt("Choose an operation", undef, ['init', 'list', 'delete']);
  }

  switch ($op) {
    case 'init' {
      my $issue_tracker = 0;
      my $time_tracker = 0;

      if (Daemon::prompt('Do you want to enable Issue Tracker support?', 'yes', ['yes', 'no']) eq 'yes') {
        $issue_tracker = Daemon::prompt('Choose an Issue Tracker', undef, Memento::IssueTracker->_get_all());
      }

      say "";
      if (Daemon::prompt('Do you want to enable Time Tracker support?', 'yes', ['yes', 'no']) eq 'yes') {
        $time_tracker = Daemon::prompt('Choose a Time Tracker', undef, Memento::TimeTracker->_get_all());
      }

      my $config = $class->_get_config();
      $config->{issue_tracker} = $issue_tracker;
      $config->{time_tracker} = $time_tracker;
      $class->_save_config($config);

      say 'Activity configurations have been saved';
    }
    case 'list' {
      say Daemon::array2table("Activity Configurations", [$class->_get_config()], {full_nested => 1});
    }
    case 'delete' {
      $class->_save_config($class->_def_config());
      say "Your Memento Activity configurations have been deleted.";
    }
  }
}

sub start {
  my $class = shift;
  my $id = shift || 0;
  my $storage = $class->_get_storage();
  my $config = $class->_get_config();
  my $issue_tracker = $config->{issue_tracker} || 0;
  my $time_tracker = $config->{time_tracker} || 0;
  my $manual = 0;

  GetOptions(
    'manual!' => \$manual,
    'issue-tracker=s' => \$issue_tracker,
    'time-tracker=s' => \$time_tracker
  ) or die 'Incorrect usage';

  # Reset $id to 0 if an option has been passed but not an ID.
  if ($id =~ /^--/) {
    $id = 0;
  }

  my $issue;
  my $activity = '';

  if (!$manual && $issue_tracker) {
    # Check if the issue tracker has been instantiated. This may happen when
    # executing a Memento git command before having initialized Memento git.
    if (!$class->{$issue_tracker}) {
      $class->{$issue_tracker} = Memento::Tool->instantiate($issue_tracker);
    }

    if (!$id) {
      $id = Daemon::prompt("Enter $issue_tracker issue id");
    }
    $issue = $class->{$issue_tracker}->_get_issue($id);
    if (!$issue) {
      die "You have specified an invalid issue id.";
    }

    say "You are going to start working on the following activity:\n";
    $class->{$issue_tracker}->_render_issue($issue);
    if (Daemon::prompt("Do you confirm?", 'yes', ['yes', 'no']) eq 'no') {
      die "Aborting...\n";
    }
    $activity = $class->{$issue_tracker}->_time_tracker_entry($issue);
  }
  else {
    $activity = Daemon::prompt("Enter activity name");
  }

  # Check if we were already working on something else.
  if ($storage->{status}) {
    my $current_activity = $storage->{activity};

    if ($activity eq $current_activity) {
      say "You were already working on this activity: " . Daemon::printColor($activity, "black on_bright_yellow");
      if (Daemon::prompt("Were you starting to work on it again?", 'no', ['yes', 'no']) eq 'no') {
        die("Aborting...\n");
      }

      say "Resuming current activity...";
      Daemon::system("memento activity resume");
      return;
    }

    say "You were already working on another activity: " . Daemon::printColor($current_activity, "black on_bright_yellow");
    if (Daemon::prompt("Do you confirm?", 'yes', ['yes', 'no']) eq 'no') {
      die("Aborting...\n");
    }

    say "Stopping previous activity...";
    Daemon::system("memento activity stop");
  }

  # Store activity info.
  $storage = {
    activity => decode('utf8', $activity),
    issue_tracker => $issue_tracker,
    issue => $issue,
    time_tracker => $time_tracker,
    id => $id,
    status => 1
  };
  $class->_save_storage($storage);

  say Daemon::printColor("Activity started", "black on_bright_yellow");
  $class->_on('activity_start', {issue => $issue});
}

sub current {
  my $class = shift;
  my $storage = $class->_get_storage();
  my $status = $storage->{status};
  my $open = 0;

  if (!$status) {
    say "You are not working on any activity at the moment.";

    if ($storage->{activity}) {
      say "Last activity you worked on was: " . Daemon::printColor($storage->{activity}, "black on_bright_yellow");
    }
    return;
  }

  GetOptions(
    'open!' => \$open
  ) or die 'Incorrect usage';

  if ($storage->{issue_tracker} && $storage->{issue}) {
    my $id = $storage->{id};
    if ($open) {
      Daemon::system("memento " . $storage->{issue_tracker} . " issue $id --open");
    }
    else {
      my $issue_tracker = Memento::Tool->instantiate($storage->{issue_tracker});
      say "You are actually working on the following activity:\n";
      $issue_tracker->_render_issue($storage->{issue}, 1);
    }
  }
  else {
    say "You are actually working on the following activity: " . Daemon::printColor($storage->{activity}, "bold white on_green")
  }
}

sub stop {
  my $class = shift;

  # Update activity status to 0.
  my $storage = $class->_get_storage();
  $storage->{status} = 0;
  $class->_save_storage($storage);

  say "\n" . Daemon::printColor("Activity stopped", "black on_bright_yellow") . "\n";
  $class->current();
  $class->_on('activity_stop', {issue => $storage->{issue}});
}

sub resume {
  my $class = shift;

  # Update activity status to 1.
  my $storage = $class->_get_storage();
  $storage->{status} = 1;
  $class->_save_storage($storage);

  say "\n" . Daemon::printColor("Activity resumed", "black on_bright_yellow") . "\n";
  $class->current();
  $class->_on('activity_resume', {issue => $storage->{issue}});
}

# OVERRIDDEN METHODS ###########################################################

sub _def_config {
  my $class = shift;

  return {
    issue_tracker => 0,
    time_tracker => 0
  };
}

# RULES ########################################################################

sub _events {
  return [
    {
      name => 'activity_start',
      arguments => [
        'issue'
      ]
    },
    {
      name => 'activity_stop',
      arguments => [
        'issue'
      ]
    },
    {
      name => 'activity_resume',
      arguments => [
        'issue'
      ]
    }
  ];
}

sub _conditions {
  return [
    {
      tool => 'activity',
      name => 'activity_check_issue_tracker',
      callback => '_check_issue_tracker',
      params => [
        {
          name => 'issue_tracker',
          label => 'Issue Tracker name'
        }
      ]
    }
  ];
}

sub _check_issue_tracker {
  my $class = shift;
  my $params = shift;
  my $storage = $class->_get_storage();

  return ($storage->{issue_tracker} && $storage->{issue_tracker} eq $params->{issue_tracker});
}

# PRIVATE METHODS ##############################################################

1;
