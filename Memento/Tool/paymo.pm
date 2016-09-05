#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Memento/TimeTracker.pm";

package Memento::Tool::paymo;

use feature 'say';
use JSON::PP;
our @ISA = qw(Memento::TimeTracker);
use strict; use warnings;
use Encode qw(encode);
use Getopt::Long;
use Switch;
use Text::Aligner;
use Text::Table;
use POSIX qw(ceil floor strftime);
use DateTime;
use DateTime::Format::Strptime;
use Data::Dumper;

our (%pager);

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
      say "Please provide your Paymo info and remember that all values are mandatory";
      $conf = {
        id => Daemon::prompt('Configuration id'),
        key => Daemon::prompt('Paymo API Key')
      };

      my $is_default = (Daemon::prompt('Set this configuration as your default one?', 'yes', ['yes', 'no']) eq 'yes');

      push(@{$config->{api}}, $conf);
      if ($is_default) {
        $config->{default} = $conf->{id};
      }

      $class->_save_config($config);
      say 'Paymo API configurations have been saved';
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
        key => Daemon::prompt('Paymo API Key', $config->{api}[$key]->{key})
      };

      $config->{api}[$key] = $conf;
      $class->_save_config($config);
      say 'Paymo API configurations have been updated';

    }
    case 'delete' {
      if (scalar(@{$config->{api}}) < 1) {
        die "Paymo API configs not found.\n";
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

      say 'Paymo API configurations have been deleted';
    }
    case 'list' {
      say Daemon::array2table("Paymo Configurations", $config->{api});

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
        say "Paymo API switched to $id";
      }
      else {
        die "Paymo API id not found: $id\n";
      }
    }
  }
}

sub clients {
  my $class = shift;
  my $data = $class->_call_api("clients");
  say Daemon::array2table("Clients", $data->{'clients'}, {exclude => ['image', 'created_on', 'updated_on']});
}

sub projects {
  my $class = shift;
  my $data = $class->_call_api("projects", {where => "active=true"});
  say Daemon::array2table("Projects", $data->{'projects'}, {exclude => ['users', 'color', 'managers', 'created_on', 'updated_on', 'budget_hours', 'billable']});
}

sub users {
  my $class = shift;
  my $data = $class->_call_api("users");
  say Daemon::array2table("Users", $data->{'users'}, {exclude => $class->_get_user_excluded_fields()});
}

sub user {
  my $class = shift;
  my $user = $class->_get_current_user();
  say Daemon::array2table("My Paymo Account", $user, {exclude => $class->_get_user_excluded_fields()});
}

sub info {
  my $class = shift;

  if (!$class->_is_default()) {
    say "Paymo has not been configured to run as time tracker for this project.";
    return;
  }

  my $storage = $class->_get_storage();
  my $git = Memento::Tool->instantiate('git');
  my $git_config = $git->_get_config();
  my $git_project = $git_config->{'project'};
  my %projects = $class->_get_projects();
  my $project_id = $storage->{projects}->{$git_project}->{project_id};
  my $task_list_id = $storage->{projects}->{$git_project}->{task_list_id};

  for my $project (keys %projects) {
    if ($projects{$project} == $project_id) {
      $storage->{projects}->{$git_project}->{project_name} = $project;
    }
  }

  my %task_list = $class->_get_task_list($project_id);
  for my $task (keys %task_list) {
    if ($task_list{$task} == $task_list_id) {
      $storage->{projects}->{$git_project}->{task_name} = $task;
    }
  }

  say Daemon::array2table("Paymo Project info", [$storage->{projects}->{$git_project}], {exclude => ['start']});
}

sub setProject {
  my $class = shift;

  if (!$class->_is_default()) {
    say "Paymo has not been configured to run as time tracker for this project.";
    return;
  }

  my $storage = $class->_get_storage();
  my $git = Memento::Tool->instantiate('git');
  my $git_config = $git->_get_config();
  my $git_project = $git_config->{'project'};

  say "";
  my %projects = $class->_get_projects();
  my $project = Daemon::prompt("Please select a Paymo project", undef, [keys %projects]);
  my $project_id = $projects{$project};
  $storage->{projects}->{$git_project}->{project_id} = $project_id;

  say "";
  my %task_list = $class->_get_task_list($project_id);
  my $task = Daemon::prompt("Choose a task list", undef, [keys %task_list]);
  my $task_list_id = $task_list{$task};
  $storage->{projects}->{$git_project}->{task_list_id} = $task_list_id;

  say "Paymo project configurations saved.";

  $class->_save_storage($storage);
}

# OVERRIDDEN METHODS ###########################################################

sub _pre {
  my ($class) = @_;
  my $config = $class->_get_config();

  if ($config->{default}) {
    Daemon::printLabel("[Memento] » Paymo: " . $config->{default});
  }
}

sub _def_config {
  return {
    api => [],
    default => undef
  };
}

# EVENT LISTENERS ##############################################################

sub _on_git_flow_start {
  my $class = shift;

  if (!$class->_is_default()) {
    return;
  }

  my $subject = shift;
  my $event = shift;
  my $params = shift;
  my $storage = $class->_get_storage();
  my $config = $class->_get_config();
  my $git = Memento::Tool->instantiate('git');
  my $git_config = $git->_get_config();
  my $git_project = $git_config->{project};

  if (!$storage->{projects}->{$git_project}) {
    $class->set_project();
  }

  $storage->{projects}->{$git_project}->{start} = $class->_get_formatted_time();
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

  my $subject = shift;
  my $event = shift;
  my $params = shift;
  my $storage = $class->_get_storage();
  my $git = Memento::Tool->instantiate('git');
  my $git_config = $git->_get_config();
  my $git_project = $git_config->{'project'};

  if ($storage->{'projects'}->{$git_project}) {
    my $issue = $params->{issue};

    my $project = $storage->{'projects'}->{$git_project};

    my $time_entry = {
      task_id => 0,
      start_time => $project->{'start'},
      end_time => $class->_get_formatted_time(),
      description => $git->_get_last_commit_message()
    };

    my $name = "";

    if ($issue) {
      my $issue_tracker = Memento::Tool->instantiate($git_config->{'issue_tracker'});
      $name = $issue_tracker->_time_tracker_entry($issue);
    }
    else {
      $name = "Git branch: " . $git->_get_current_branch();
    }

    my $task_data = {
      name => $name,
      tasklist_id => $project->{'task_list_id'}
    };
    my $task = $class->_retrieve_task($task_data, $project);
    $task->{'name'} = encode('utf8', $task->{'name'});

    my $task_info = $task;
    $task_info->{'start_time'} = $project->{'start'};
    say Daemon::array2table("Paymo Time Entry", [$task_info], {exclude => $class->_get_task_excluded_fields()});

    if ($task && (Daemon::prompt('Do you want to save worked time on Paymo?', 'yes', ['yes', 'no']) eq 'yes')) {
      $time_entry->{'task_id'} = $task->{'id'};
      my $response = $class->_call_api("entries", $time_entry, 'POST');
    }
  }
}

# RULES ########################################################################

sub _conditions {
  return [
    {
      tool => 'paymo',
      name => 'paymo_check_default_api',
      callback => '_check_default_api',
      params => [
        {
          name => 'paymo_api_id',
          label => 'Paymo API ID'
        }
      ]
    }
  ];
}

sub _check_default_api {
  my $class = shift;
  my $params = shift;
  my $config = $class->_get_config();
  return ($config->{default} eq $params->{paymo_api_id});
}

# PRIVATE METHODS ##############################################################

sub _get_current_user {
  my $class = shift;
  my $data = $class->_call_api("me");
  return $data->{'users'};
}

sub _get_projects {
  my $class = shift;
  my $data = $class->_call_api("projects", {where => "active=true"});
  my %projects;

  foreach my $project (@{$data->{'projects'}}) {
    $projects{$project->{name}} = $project->{id};
  }

  return %projects;
}

sub _get_task_list {
  my $class = shift;
  my $project_id = shift;
  my $query = {};

  if ($project_id) {
    $query->{where} = "project_id=$project_id";
  }

  my $data = $class->_call_api("tasklists", $query);
  my %tasklists;

  foreach my $task (@{$data->{'tasklists'}}) {
    $tasklists{$task->{name}} = $task->{id};
  }

  return %tasklists;
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

  die "Cannot find Paymo API configurations saved with id $id\n";
}

sub _call_api {
  my $class = shift;
  my $path = shift;
  my $query = shift || {};
  my $method = shift || 'GET';
  my $config = $class->_get_config();

  if (!$config) {
    say "No Paymo configuration has been found: creating a new configuration...";
    $class->config('add');
    die "\n";
  }

  if (!$config->{default}) {
    die "Please configure (switch to) a default Paymo Api configuration\n";
  }

  my $api_id = $config->{default};
  my $settings = $class->_config_load($api_id);
  my $key = $settings->{key};
  my $paymo_url = 'https://app.paymoapp.com/api';
  my $uri = "$paymo_url/$path";

  if ($method eq 'GET') {
    GetOptions(
      'api-id=s' => \$api_id,
    ) or die 'Incorrect usage';
  }

  my $CURLOPT_USERPWD = 10005;
  my $response = Daemon::http_request($method, $uri, $query, ["Accept: application/json"], {$CURLOPT_USERPWD => $key});
  my $content = decode_json $response;

  return $content;
};

sub _name {
  return 'paymo';
}

sub _retrieve_task {
  my $class = shift;
  my $task = shift;
  my $project = shift;
  my $tasks = {};

  my $query = {where => "project_id=" . $project->{'project_id'} . " and name=\"" . $task->{name} . "\""};
  my $response = $class->_call_api("tasks", $query);

  if (scalar @{$response->{tasks}} < 1) {
    $response = $class->_call_api("tasks", $task, 'POST');
  }

  if ($response->{'tasks'}) {
    $task = shift @{$response->{'tasks'}};
    return $task;
  }
  else {
    die "There was an error while trying to retrieve the correct Paymo task\n";
  }
}

sub _get_formatted_time {
  return strftime "%FT%T%Z", localtime;
}

sub _get_user_excluded_fields {
  return [
    'additional_privileges',
    'assigned_projects',
    'created_on',
    'date_format',
    'image',
    'image_thumb_large',
    'image_thumb_medium',
    'image_thumb_small',
    'price_per_hour',
    'time_format',
    'updated_on',
    'managed_projects'
  ];
}

sub _get_task_excluded_fields {
  return [
    'updated_on',
    'users',
    'price_per_hour',
    'budget_hours',
    'complete',
    'created_on',
    'billable',
    'description',
    'seq',
    'due_date'
  ];
}

1;