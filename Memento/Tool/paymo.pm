#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Memento/TimeTracker.pm";

package Memento::Tool::paymo;

use feature 'say';
use JSON::PP;
our @ISA = qw(Memento::TimeTracker);
use strict; use warnings;
use Data::Dumper;
use Encode qw(encode);
use Getopt::Long;
use Switch;
use Text::Aligner;
use Text::Table;
use POSIX qw(ceil floor);

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
  my $data = $class->_call_api("projects");
  say Daemon::array2table("Projects", $data->{'projects'}, {exclude => ['users', 'color', 'managers', 'created_on', 'updated_on', 'budget_hours', 'billable']});
}

sub users {
  my $class = shift;
  my $data = $class->_call_api("users");
  say Daemon::array2table("Users", $data->{'users'}, {exclude => [
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
  ]});
}

sub user {
  my $class = shift;
  my $user = $class->_get_current_user();
  say Daemon::array2table("My Paymo Account", $user, {exclude => [
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
 ]});
}

# OVERRIDDEN METHODS ###########################################################

sub _pre {
  my ($class) = @_;
  my $config = $class->_get_config();

  if ($config->{default}) {
    Daemon::printLabel($config->{default});
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
  my $subject = shift;
  my $event = shift;
  my $params = shift;
  my $storage = $class->_get_storage();
  my $config = $class->_get_config();
  my $git = Memento::Tool->instantiate('git');
  my $git_config = $git->_get_config();
  my $git_project = $git_config->{project};

  if (!$storage->{projects}->{$git_project}) {
    say "";
    my %projects = $class->_get_projects();
    my $project = Daemon::prompt("Bind this project to a Paymo project", undef, [keys %projects]);
    my $project_id = $projects{$project};

    say "";
    my %task_list = $class->_get_task_list($project_id);
    my $task = Daemon::prompt("Choose a task list", undef, [keys %task_list]);
    my $task_list_id = $task_list{$task};

    $storage->{projects}->{$git_project} = {
      project_id => $project_id,
      task_list_id => $task_list_id,
      time_entries => {}
    };
    $class->_save_storage($storage);
  }
}

sub __on_git_post_commit {
  my $class = shift;
  my $subject = shift;
  my $event = shift;
  my $params = shift;

  my $git = Memento::Tool->instantiate('git');
  my $issue = $git->_get_issue();

  if ($issue) {
    my $data = {};
    $data->{issue}->{notes} = "*[memento]* " . $git->_get_pretty_commit_message();
    $class->_call_api("issues/" . $issue->{id}, $data, 'PUT');
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

sub __actions {
  return [
    {
      tool => 'redmine',
      name => 'redmine_change_issue_status',
      callback => '_change_issue_status',
      arguments => [
        'issue'
      ],
      params => [
        {
          name => 'done_ratio',
          label => 'Done ratio',
          options => '_get_done_ratio'
        },
        {
          name => 'status',
          label => 'Issue status',
          options => '_get_issue_statuses'
        }
      ]
    }
  ];
}

# PRIVATE METHODS ##############################################################

sub _get_done_ratio {
  my $class = shift;
  return [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100];
}

sub _get_issue {
  my $class = shift;
  my $id = shift or die "Missing issue id to load";
  my $data = $class->_call_api("issues/$id", {include => "attachments"});
  return $data->{issue};
}

sub _get_issue_statuses {
  my $class = shift;
  my $full = shift;
  my $data = $class->_call_api("issue_statuses");
  my $statuses = [];

  foreach my $status (@{$data->{issue_statuses}}) {
    if ($full) {
      push(@{$statuses}, $status);
    }
    else {
      push(@{$statuses}, $status->{name});
    }
  }

  return $statuses;
}

sub _get_current_user {
  my $class = shift;
  my $data = $class->_call_api("me");
  return $data->{'users'};
}

sub _get_projects {
  my $class = shift;
  my $data = $class->_call_api("projects");
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

sub _get_project_memberships {
  my $class = shift;
  my $project_id = shift or die "Missing project id argument";
  my $data = $class->_call_api("projects/$project_id/memberships", {limit => 1});
  $data = $class->_call_api("projects/$project_id/memberships", {limit => $data->{total_count}});
  return $data->{'memberships'};
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
  my $content = ($method eq 'GET') ? decode_json $response : $response;

  return $content;
};

1;