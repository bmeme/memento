#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Memento/IssueTracker.pm";

package Memento::Tool::taiga;

use feature 'say';
use JSON::PP;
our @ISA = qw(Memento::IssueTracker);
use strict; use warnings;
use Encode qw(encode);
use Getopt::Long;
use Switch;
use Text::Aligner;
use Text::Table;
use POSIX qw(ceil floor);
use MIME::Base64;
use Data::Dumper;

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
      say "Please provide your Taiga info and remember that all values are mandatory";
      my $id = Daemon::prompt('Configuration id');
      my $username = Daemon::prompt('Taiga username');
      my $password = Daemon::prompt('Taiga password');
      my $url = Daemon::prompt('Taiga URL');

      my $conf = {
        id => $id,
        username => $username,
        password => $password,
        url => $url
      };

      my $is_default = (Daemon::prompt('Set this configuration as your default one?', 'yes', ['yes', 'no']) eq 'yes');

      push(@{$config->{api}}, $conf);
      if ($is_default) {
        $config->{default} = $conf->{id};
      }

      $class->_save_config($config);
      say 'Taiga API configurations have been saved';
    }
    case 'edit' {
      my $key = Daemon::prompt('Choose an api id', undef, $class->_get_api_ids());

      my $id = $config->{api}[$key]->{id};
      my $username = Daemon::prompt('Taiga username');
      my $password = Daemon::prompt('Taiga password');
      my $url = Daemon::prompt('Taiga URL', $config->{api}[$key]->{url});

      my $conf = {
        id => $id,
        username => $username,
        password => $password,
        url => $url
      };

      $config->{api}[$key] = $conf;
      $class->_save_config($config);
      say 'Taiga API configurations have been updated';

    }
    case 'delete' {
      if (scalar(@{$config->{api}}) < 1) {
        die "Taiga API configs not found.\n";
      }

      my $key = Daemon::prompt('Choose an api id to delete', undef, $class->_get_api_ids());
      delete $config->{api}[$key];
      $class->_save_config($config);
      say 'Taiga API configurations have been deleted';
    }
    case 'list' {
      say Daemon::array2table("Taiga Configurations", $config->{api});

      if ($config->{default}) {
        say "Default: $config->{default}";
      }
    }
    case 'switch' {
      my @api_id_names = $class->_get_api_id_names();
      my $id = $_[0] || Daemon::prompt("Enter the API id to switch into", undef, @api_id_names);
      if (Daemon::in_array(@api_id_names, $id)) {
        $config->{default} = $id;
        $class->_save_config($config);
        say "Taiga API switched to $id";
      }
      else {
        die "Taiga API id not found: $id\n";
      }
    }
  }
}

sub issue {
  my $class = shift;
  my $id = shift;
  my $open = 0;

  if (!$id) {
    $id = Daemon::prompt('Enter the issue/task ID (eg: task/12 or issue/3)');
  }

  GetOptions(
    'open!' => \$open
  ) or die 'Incorrect usage';

  my ($type, $ref) = split('/', $id);
  my $types = ['task', 'issue'];

  if (!$type || !Daemon::in_array($types, $type)) {
    die("Undefined type: the issue ID has to be something like issue/ISSUE_ID or task/TASK_ID\n");
  }

  if ($open) {
    my $config = $class->_get_config();
    my $settings = $class->_config_load($config->{default});
    my $project = $class->_get_storage_project();
    my $slug = $project->{project_slug};
    my $uri = $settings->{url} . "/project/$slug/$id";
    Daemon::open_default_browser($uri);
  }
  else {
    my $issue = $class->_get_issue($id);
    $class->_render_issue($issue, 1);
  }
}

sub projects {
  my $class = shift;
  my $data = $class->_call_api("projects");
  my $projects = [];

  foreach my $project (@{$data}) {
    push(@{$projects}, {
      id => $project->{id},
      name => $project->{name},
      description => $project->{description}
    });
  }
  say Daemon::array2table("Projects", $projects);
}

sub user {
  my $class = shift;
  my $data = $class->_get_current_user();
  my $user = {
    id => $data->{id},
    email => $data->{email},
    full_name => $data->{full_name},
    username => $data->{username},
    lang => $data->{lang},
  };
  say Daemon::array2table("My Taiga Account", [$user]);
}

sub search {
  my $class = shift;
  my $query = {};

  GetOptions(
    'project=i' => \$query->{project},
    'closed=s' => \$query->{status__is_closed},
    'assigned=i' => \$query->{assigned_to}
  ) or die 'Incorrect usage';

  delete $query->{project} if !$query->{project};
  delete $query->{status__is_closed} if !$query->{status__is_closed};
  delete $query->{assigned_to} if !$query->{assigned_to};

  my $data = $class->_call_api("tasks", $query);
  if (!$data) {
    say "No results found for this search";
    return;
  }

  my $issues = [];
  foreach my $issue (@{$data}) {
    push(@{$issues}, $class->_build_search_result($issue));
  }

  say Daemon::array2table("Tasks", $issues);
}

sub setProject {
  my $class = shift;

  if (!$class->_is_default()) {
    say "Taiga has not been configured to run as issue tracker for this project.";
    return;
  }

  my $storage = $class->_get_storage();
  my $git = Memento::Tool->instantiate('git');
  my $git_config = $git->_get_config();
  my $git_project = $git_config->{'project'};

  say "";
  my %projects = $class->_get_projects();
  my $project = Daemon::prompt("Please select a Taiga project", undef, [sort keys %projects]);
  my $project_slug = $projects{$project};
  $storage->{projects}->{$git_project}->{project_slug} = $project_slug;

  say "Taiga project configurations saved.";

  $class->_save_storage($storage);
}

# OVERRIDDEN METHODS ###########################################################

sub _pre {
  my ($class) = @_;
  my $config = $class->_get_config();

  if ($config->{default}) {
    Daemon::printLabel("[Memento] » Taiga: " . $config->{default});
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

  if ($params->{issue}) {
    $storage->{issues}->{$params->{branch}} = {
      issue_id => $params->{issue}->{type} . '/' . $params->{issue}->{'ref'},
      taiga_api_id => $config->{default}
    };
    $class->_save_storage($storage);
  }
}

sub _on_schema_check {
  my $class = shift;
  my $config = $class->_get_config();
  if (!$config->{default}) {
    return;
  }

  my $user = $class->_get_current_user();

  my $settings = $class->_get_settings();
  my $username = $settings->{username};
  my $query = {'assigned_to' => $user->{id}, 'status__is_closed' => 'false'};
  my $data = $class->_call_api("tasks", $query);

  if (!$data->{issues}) {
    return;
  }

  my $issues = [];
  foreach my $issue (@{$data->{issues}}) {
    push(@{$issues}, $class->_build_search_result($issue));
  }

  Daemon::printLabel("[Memento] » Taiga");
  say Daemon::array2table("Your open tasks", $issues);
}

# RULES ########################################################################

sub _conditions {
  return [
    {
      tool => 'taiga',
      name => 'taiga_check_default_api',
      callback => '_check_default_api',
      params => [
        {
          name => 'taiga_api_id',
          label => 'Taiga API ID'
        }
      ]
    }
  ];
}

sub _check_default_api {
  my $class = shift;
  my $params = shift;
  if (!$class->_is_default()) {
    return 0;
  }
  my $config = $class->_get_config();
  return ($config->{default} eq $params->{taiga_api_id});
}

sub _actions {
  return [
    {
      tool => 'taiga',
      name => 'taiga_change_issue_status',
      callback => '_change_issue_status',
      arguments => [
        'issue'
      ]
    }
  ];
}

sub _change_issue_status {
  my $class = shift;
  my $arguments = shift;
  my $params = shift;

  if ($arguments->{issue}) {
    my $issue = $arguments->{issue};
    my $user = $class->_get_current_user();
    my $data = {};

    if (Daemon::prompt("Do you want to change the issue assignee?", 'yes', ['yes', 'no']) eq 'yes') {
      my %assignees = $class->_get_assignable_users();
      my $assignee = Daemon::prompt("Choose an assignee", undef, [sort keys %assignees]);
      $issue->{assigned_to} = $assignees{$assignee}->{id};
      $issue->{assigned_to_extra_info} = $assignees{$assignee};
    }

    if (Daemon::prompt("Do you want to change the issue status?", 'yes', ['yes', 'no']) eq 'yes') {
      my %transitions = $class->_get_issue_transitions($issue);
      my $transition = Daemon::prompt("Choose a status", undef, [sort keys %transitions]);
      $issue->{status} = $transitions{$transition}->{id};
    }

    $class->_call_api($issue->{type} . "s/" . $issue->{id}, $issue, 'PUT');
    print "\n";
    $class->_render_issue($class->_get_issue($issue->{type} . "/" . $issue->{'ref'}));
  }
}

# PRIVATE METHODS ##############################################################

sub _get_assignable_users {
  my $class = shift;
  my $project = $class->_get_current_project();
  my %users;

  foreach my $user (@{$project->{members}}) {
    $users{encode('utf8', $user->{full_name})} = $user;
  }

  return %users;
}

sub _get_issue_transitions {
  my $class = shift;
  my $issue = shift;
  my $project = $class->_get_current_project();
  my %transitions;

  foreach my $transition (@{$project->{$issue->{type} . '_statuses'}}) {
    $transitions{encode('utf8', $transition->{name})} = $transition;
  }

  return %transitions;
}

sub _get_issue {
  my $class = shift;
  my $id = shift or die "Missing issue/task id to load";
  my ($type, $ref) = split('/', $id);
  my $project = $class->_get_storage_project();
  my $issue = $class->_call_api($type . "s/by_ref", {'ref' => $ref, 'project__slug' => $project->{project_slug}});
  $issue->{type} = $type;
  return $issue;
}

sub _get_storage_project {
  my $class = shift;
  my $storage = $class->_get_storage();
  my $git = Memento::Tool->instantiate('git');
  my $git_config = $git->_get_config();
  my $git_project = $git_config->{'project'};
  my $project = $storage->{'projects'}->{$git_project};

  if (!$project) {
    $class->setProject();
    # Reload updated storage.
    $storage = $class->_get_storage();
    $project = $storage->{'projects'}->{$git_project};
  }
  return $project;
}

sub _get_current_user {
  my $class = shift;
  return $class->_call_api("myself");
}

sub _get_projects {
  my $class = shift;
  my $user = $class->_get_current_user();
  my $data = $class->_call_api("projects", {'member' => $user->{id}});
  my %projects;

  foreach my $project (@{$data}) {
    $projects{$project->{name}} = $project->{slug};
  }

  return %projects;
}

sub _get_current_project {
  my $class = shift;
  my $storage_project = $class->_get_storage_project();
  my $project = $class->_call_api("projects/by_slug", {slug => $storage_project->{project_slug}});
  return $project;
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

  die "Cannot find Taiga API configurations saved with id $id\n";
}

sub _call_api {
  my $class = shift;
  my $path = shift;
  my $query = shift || {};
  my $method = shift || 'GET';
  my $config = $class->_get_config();

  if (!$config) {
    say "No Taiga configuration has been found: creating a new configuration...";
    $class->config('add');
    die "\n";
  }

  if (!$config->{default}) {
    die "Please configure (switch to) a default Taiga Api configuration\n";
  }

  my $api_id = $config->{default};
  my $settings = $class->_config_load($api_id);
  my $username = $settings->{username};
  my $password = $settings->{password};
  my $taiga_url = $settings->{url};
  my $uri = "$taiga_url/api/v1/auth";

  my $authParams = {
    password => $password,
    type => "normal",
    username => $username
  };
  my $user = decode_json Daemon::http_request('POST', $uri, $authParams, {
   "Content-Type" => "application/json; charset=UTF-8"
  });

  if ($path eq 'myself') {
    return $user;
  }

  my $token = $user->{auth_token};
  $uri = "$taiga_url/api/v1/$path";

  my $response = Daemon::http_request($method, $uri, $query, {
    "Content-Type" => "application/json; charset=UTF-8",
    "Authorization" => "Bearer $token"
  });
  my $content = ($method eq 'GET') ? decode_json $response : $response;

  return $content;
}

sub _get_settings {
  my $class = shift;
  my $config = $class->_get_config();
  my $api_id = $config->{default};
  my $settings = $class->_config_load($api_id);
  return $settings;
}

sub _render_issue {
  my $class = shift;
  my $issue = shift;
  my $full = shift;
  my $title = sprintf("[%s] #%s - %s", $issue->{'project_extra_info'}->{'name'}, $issue->{'ref'}, $issue->{'subject'});
  my $bg_color = ($issue->{'status'} == 5) ? "green" : (($issue->{'status_extra_info'}->{'name'} eq 'New') ? "blue" : "yellow");

  Daemon::printLabel($title, "bold white on_$bg_color");
  say sprintf("|- %s: %s", $issue->{type}, encode('utf8', $issue->{'status_extra_info'}->{'name'}));
  say sprintf("|- Created by: %s on %s", $issue->{'owner_extra_info'}->{'full_name_display'}, $issue->{'created_date'});
  say sprintf("|- Assigned to: %s\n", $issue->{'assigned_to_extra_info'}->{'full_name_display'}) if defined $issue->{'assigned_to_extra_info'};

  if ($full) {
    Daemon::printLabel("Description");
    say encode('utf8', $issue->{'description'});
  }
}

sub _name {
  return 'taiga';
}

sub _branch_pattern {
  return ':ref:-:subject:';
}

sub _time_tracker_entry {
  my $class = shift;
  my $issue = shift;
  return  "#" . $issue->{'id'} . " - " . $issue->{'subject'};
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

sub _build_search_result {
  my $class = shift;
  my $issue = shift;
  return {
    issue_id => $issue->{ref},
    subject => $issue->{subject},
    assignee_id => $issue->{'assigned_to_extra_info'}->{'id'},
    assignee => $issue->{'assigned_to_extra_info'}->{'full_name_display'},
    creator => $issue->{'owner_extra_info'}->{'full_name_display'},
    project_id => $issue->{'project_extra_info'}->{'id'},
    project => $issue->{'project_extra_info'}->{'name'},
    status => $issue->{'status_extra_info'}->{'name'}
  };
}

1;