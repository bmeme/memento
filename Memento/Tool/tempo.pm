#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Memento/TimeTracker.pm";

package Memento::Tool::tempo;

use feature 'say';
use JSON::PP;
our @ISA = qw(Memento::TimeTracker);
use strict; use warnings;
use Encode qw(encode);
use Getopt::Long;
use Switch;
use Text::Aligner;
use Text::Table;
use Text::Trim;
use POSIX qw(ceil floor strftime);
use DateTime;
use DateTime::Format::Strptime;
use Data::Dumper;

our (%pager, $api_token);
$api_token = "";

sub config {
  my $class = shift;
  my $op = shift;
  my $config = $class->_get_config();
  my $operations = ['add', 'edit', 'delete', 'list', 'switch'];

  if (!$op || !Daemon::in_array($operations, $op)) {
    $op = Daemon::prompt("Choose an operation", undef, $operations);
  }

  switch ($op) {
    case 'add' {
      my $conf;
      say "Please provide your Tempo info and remember that all values are mandatory";
      $conf = {
        id => Daemon::prompt('Configuration id'),
        key => Daemon::prompt('Tempo API Token (Go to Tempo > Settings and select API integration)')
      };

      $api_token = $conf->{key};
      my %members = $class->_get_members();
      my $member = Daemon::prompt("Please tell me who you are", undef, [sort keys %members]);
      my $member_id = $members{$member};
      $conf->{accountId} = $member_id;

      my $is_default = (Daemon::prompt('Set this configuration as your default one?', 'yes', ['yes', 'no']) eq 'yes');

      push(@{$config->{api}}, $conf);
      if ($is_default) {
        $config->{default} = $conf->{id};
      }

      $class->_save_config($config);
      say 'Tempo API configurations have been saved';
    }
    case 'edit' {
      my $api_ids;
      my $i = 0;

      foreach my $api (@{$config->{api}}) {
        $api_ids->{$api->{id}} = $i;
        $i++;
      }

      my $key = Daemon::prompt('Choose an api id', undef, $api_ids);
      my $conf = {
        id => $config->{api}[$key]->{id},
        key => Daemon::prompt('Tempo API Token', $config->{api}[$key]->{key})
      };

      $api_token = $conf->{key};
      my %members = $class->_get_members();
      my $member = Daemon::prompt("Please tell me who you are", undef, [sort keys %members]);
      my $member_id = $members{$member};
      $conf->{accountId} = $member_id;

      $config->{api}[$key] = $conf;
      $class->_save_config($config);
      say 'Tempo API configurations have been updated';

    }
    case 'delete' {
      if (scalar(@{$config->{api}}) < 1) {
        die "Tempo API configs not found.\n";
      }

      my $api_ids;
      my $i = 0;

      foreach my $api (@{$config->{api}}) {
        $api_ids->{$api->{id}} = $i;
        $i++;
      }
      my $key = Daemon::prompt('Choose an api id to delete', undef, $api_ids);

      delete $config->{api}[$key];
      $class->_save_config($config);

      say 'Tempo API configurations have been deleted';
    }
    case 'list' {
      say Daemon::array2table("Tempo Configurations", $config->{api});

      if ($config->{default}) {
        say "Default: $config->{default}";
      }
    }
    case 'switch' {
      my $id = $_[0] || Daemon::prompt("Enter the API id to switch into");
      my $found = 0;
      for my $item (@{$config->{api}}) {
        if ($item->{id} eq $id) {
          $found = 1;
        }
      }

      if ($found) {
        $config->{default} = $id;
        $class->_save_config($config);
        say "Tempo API switched to $id";
      }
      else {
        die "Tempo API id not found: $id\n";
      }
    }
  }
}

sub teams {
  my $class = shift;
  my $data = $class->_call_api("teams");
  say Daemon::array2table("Teams", $data->{'results'}, {exclude => ['self', 'lead', 'program', 'links', 'members', 'permissions']});
}

sub members {
  my $class = shift;
  my %teams = $class->_get_teams();
  my $team = Daemon::prompt("Please select a Tempo team", undef, [sort keys %teams]);
  my $team_id = $teams{$team};
  my $data = $class->_call_api("teams/$team_id/members");
  my $members = [];

  foreach my $member (@{$data->{results}}) {
    push(@{$members}, $member->{member});
  }

  say Daemon::array2table("Members", $members, {exclude => ['self', 'accountId']});
}

# OVERRIDDEN METHODS ###########################################################

sub _pre {
  my ($class) = @_;
  my $config = $class->_get_config();

  if ($config->{default}) {
    Daemon::printLabel("[Memento] » Tempo: " . $config->{default});
  }
}

sub _def_config {
  return {
    api => [],
    accountId => undef,
    default => undef
  };
}

# EVENT LISTENERS ##############################################################

sub _on_activity_start {
  my $class = shift;
  my $activity = Memento::Tool->instantiate('activity');
  my $activity_storage = $activity->_get_storage();

  if (!$activity_storage->{time_tracker} || $activity_storage->{time_tracker} ne $class->_name()) {
    return;
  }
  $class->_ensure_consistency();

  my $storage = $class->_get_storage();
  my $activity_key = $activity_storage->{id};

  $storage->{activities}->{$activity_key}->{start} = $class->_get_formatted_time();
  $class->_save_storage($storage);
}

sub _on_activity_resume {
  my $class = shift;
  $class->_on_activity_start(@_);
}

sub _on_activity_stop {
  my $class = shift;
  my $activity = Memento::Tool->instantiate('activity');
  my $activity_storage = $activity->_get_storage();

  if (!$activity_storage->{time_tracker} || ($activity_storage->{time_tracker} ne $class->_name())) {
    return;
  }

  if ($activity_storage->{issue_tracker} ne 'jira' || !$activity_storage->{issue}) {
    $class->_trigger_inconsistency_error();
  }

  $class->_save_worklog('activities', $activity_storage->{issue}, 1);
}

sub _on_git_flow_start {
  my $class = shift;

  if (!$class->_is_default()) {
    return;
  }
  $class->_ensure_consistency();

  my $subject = shift;
  my $event = shift;
  my $params = shift;

  if (!$params->{issue}) {
    die("Missing issue parameter on git flow start\nAborting...\n");
  }

  my $issue = $params->{issue};
  my $issue_key = $issue->{key};
  my $storage = $class->_get_storage();

  $storage->{issues}->{$issue_key}->{start} = $class->_get_formatted_time();
  $class->_save_storage($storage);
}

sub _on_git_flow_pause {
  my $class = shift;
  $class->_on_git_flow_finish(@_);
}

sub _on_git_flow_resume {
  my $class = shift;
  $class->_on_git_flow_start(@_);
}

sub _on_git_flow_finish {
  my $class = shift;

  if (!$class->_is_default()) {
    return;
  }
  $class->_ensure_consistency();

  my $subject = shift;
  my $event = shift;
  my $params = shift;

  if (!$params->{issue}) {
    die("Missing issue parameter on git flow finish\nAborting...\n");
  }

  $class->_save_worklog('issues', $params->{issue});
}

# RULES ########################################################################

sub _conditions {
  return [
    {
      tool => 'tempo',
      name => 'tempo_check_default_api',
      callback => '_check_default_api',
      params => [
        {
          name => 'tempo_api_id',
          label => 'Tempo API ID'
        }
      ]
    }
  ];
}

sub _check_default_api {
  my $class = shift;
  my $params = shift;
  my $config = $class->_get_config();
  return ($config->{default} eq $params->{tempo_api_id});
}

# PRIVATE METHODS ##############################################################

sub _get_teams {
  my $class = shift;
  my $data = $class->_call_api("teams");
  my %teams;

  foreach my $team (@{$data->{'results'}}) {
    $teams{$team->{name}} = $team->{id};
  }

  return %teams;
}

sub _get_members {
  my $class = shift;
  my %teams = $class->_get_teams();
  my $team = Daemon::prompt("Please select a Tempo team", undef, [sort keys %teams]);
  my $team_id = $teams{$team};
  my $data = $class->_call_api("teams/$team_id/members");

  my %members;

  foreach my $member (@{$data->{'results'}}) {
    $members{$member->{member}->{displayName}} = $member->{member}->{accountId};
  }

  return %members;
}

sub _save_worklog {
  my $class = shift;
  my $type = shift;
  my $issue = shift;
  my $require_description = shift || 0;
  my $issue_id = $issue->{key};

  my $api_id = $class->_get_current_api_id();
  my $config = $class->_config_load($api_id);

  my $storage = $class->_get_storage();
  my $git = Memento::Tool->instantiate('git');

  my $format = DateTime::Format::Strptime->new(
     pattern    => '%Y-%m-%dT%H:%M:%S',
     time_zone => 'local',
     on_error  => 'croak',
  );
  my $date_format = DateTime::Format::Strptime->new(
     pattern    => '%Y-%m-%d',
     time_zone => 'local',
     on_error  => 'croak',
  );
  my $time_format = DateTime::Format::Strptime->new(
     pattern    => '%H:%M:%S',
     time_zone => 'local',
     on_error  => 'croak',
  );

  my $start = $storage->{$type}->{$issue_id}->{start};
  my $start_date = $format->parse_datetime($start);
  my $end = $class->_get_formatted_time();
  my $end_date = DateTime->now(time_zone => 'local');

  my $duration = $end_date->delta_ms($start_date);

  if ($duration->in_units('days') > 0 && Daemon::prompt("It seems like you've started working on this issue " . $duration->{days} . " days ago... I mean... really?\nAre you sure you want to log this time?", 'no', ['yes', 'no']) eq 'no') {
    say("Take some rest :)\nAborting...");
    return;
  }
  my $seconds = $duration->in_units('seconds') + ($duration->in_units('minutes') * 60) + ($duration->in_units('days') * 60 * 60 * 24);

  if ($seconds < 60) {
    say("Worked time ($seconds seconds) must be greater than 1 minute\nAborting...");
    return;
  }

  my $description = "";
  if ($require_description) {
    $description = trim Daemon::prompt("Please provide a description");
  }
  else {
    $description = $git->_get_last_commit_message();
  }

  my $worklog = {
    issueKey => $issue->{key},
    timeSpentSeconds => $seconds,
    startDate => $date_format->format_datetime($start_date),
    startTime => $time_format->format_datetime($start_date),
    description => $description,
    authorAccountId => $config->{accountId}
  };

  say Daemon::array2table("Tempo Worklog", [$worklog], {exclude => ['authorAccountId']});

  if (Daemon::prompt('Do you want to save worked time on Tempo?', 'yes', ['yes', 'no']) eq 'yes') {
    my $response = $class->_call_api("worklogs", $worklog, 'POST');
  }
}

sub _config_load {
  my $class = shift;
  my $id = shift or die "Missing config id to load";
  my $config = $class->_get_config();
  for my $item (@{$config->{api}}) {
    if ($item->{id} eq $id) {
      return $item;
    }
  }

  die "Cannot find Tempo API configurations saved with id $id\n";
}

sub _call_api {
  my $class = shift;
  my $path = shift;
  my $query = shift || {};
  my $method = shift || 'GET';
  my $config = $class->_get_config();

  if (!$config) {
    say "No Tempo configuration has been found: creating a new configuration...";
    $class->config('add');
    die "\n";
  }

  if (!$api_token && !$config->{default}) {
    die "Please configure (switch to) a default Tempo Api configuration\n";
  }

  my $tempo_url = "https://api.tempo.io/core/3";
  my $uri = "$tempo_url/$path";

  my $key = "";
  if ($api_token) {
    $key = $api_token;
  }
  else {
    my $api_id = $class->_get_current_api_id();

    if ($method eq 'GET') {
      GetOptions(
        'api-id=s' => \$api_id,
      ) or die 'Incorrect usage';
    }

    my $settings = $class->_config_load($api_id);
    $key = $settings->{key};
  }

  my $headers = {
    "Accept" => "application/json",
    "Content-Type" => "application/json",
    "Authorization" => "Bearer $key"
  };
  my $response = Daemon::http_request($method, $uri, $query, $headers);

  return decode_json $response;
};

sub _name {
  return 'tempo';
}

sub _get_formatted_time {
  return strftime "%FT%T%Z", localtime;
}

sub _ensure_consistency {
  my $class = shift;
  my $git = Memento::Tool->instantiate('git');
  my $git_config = $git->_get_config();

  if (!$git_config->{issue_tracker}) {
    $class->_trigger_inconsistency_error();
  }

  my $issue_tracker = Memento::Tool->instantiate($git_config->{issue_tracker});

  if ($issue_tracker->_name() ne 'jira') {
    $class->_trigger_inconsistency_error();
  }
}

sub _trigger_inconsistency_error {
  say("Tempo can be used only in conjunction with Jira issue tracker");
  die("Aborting...\n");
}

1;