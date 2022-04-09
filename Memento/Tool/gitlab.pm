#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Memento/IssueTracker.pm";

package Memento::Tool::gitlab;

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
      say "Please provide your Gitlab info and remember that all values are mandatory";
      my $id = Daemon::prompt('Configuration id');
      my $token = Daemon::prompt('Gitlab access token');
      my $url = Daemon::prompt('Gitlab URL');

      my $conf = {
        id => $id,
        token => $token,
        url => $url
      };

      my $is_default = (Daemon::prompt('Set this configuration as your default one?', 'yes', ['yes', 'no']) eq 'yes');

      push(@{$config->{api}}, $conf);
      if ($is_default) {
        $config->{default} = $conf->{id};
      }

      $class->_save_config($config);
      say 'Gitlab API configurations have been saved';
    }
    case 'edit' {
      my $key = Daemon::prompt('Choose an api id', undef, $class->_get_api_ids());

      my $id = $config->{api}[$key]->{id};
      my $token = Daemon::prompt('Gitlab access token');
      my $url = Daemon::prompt('Gitlab URL', $config->{api}[$key]->{url});

      my $conf = {
        id => $id,
        token => $token,
        url => $url
      };

      $config->{api}[$key] = $conf;
      $class->_save_config($config);
      say 'Gitlab API configurations have been updated';

    }
    case 'delete' {
      if (scalar(@{$config->{api}}) < 1) {
        die "Gitlab API configs not found.\n";
      }

      my $key = Daemon::prompt('Choose an api id to delete', undef, $class->_get_api_ids());
      delete $config->{api}[$key];
      $class->_save_config($config);
      say 'Gitlab API configurations have been deleted';
    }
    case 'list' {
      say Daemon::array2table("Gitlab Configurations", $config->{api});

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
        say "Gitlab API switched to $id";
      }
      else {
        die "Gitlab API id not found: $id\n";
      }
    }
  }
}

sub issue {
  my $class = shift;
  my $id = shift;
  my $open = 0;

  if (!$id) {
    $id = Daemon::prompt('Enter the issue ID');
  }

  GetOptions(
    'open!' => \$open
  ) or die 'Incorrect usage';

  my $issue = $class->_get_issue($id);

  if ($open) {
    Daemon::open_default_browser($issue->{web_url});
  }
  else {
    $class->_render_issue($issue, 1);
  }
}

sub projects {
  my $class = shift;
  my $data = $class->_call_api("projects", {'simple' => 1});
  say Daemon::array2table("Projects", $data, {exclude => ['http_url_to_repo', 'name', 'path']});
}

sub user {
  my $class = shift;
  my $user = $class->_get_current_user();
  my $users = [
    {
      id => $user->{id},
      username => $user->{username},
      email => $user->{email},
      name => $user->{name},
      state => $user->{state},
      web_url => $user->{web_url}
    }
  ];
  say Daemon::array2table("My Gitlab Account", $users);
}

# OVERRIDDEN METHODS ###########################################################

sub _pre {
  my ($class) = @_;
  my $api_id = $class->_get_current_api_id();

  if ($api_id) {
    Daemon::printLabel("[Memento] » Gitlab: " . $api_id);
  }
}

sub _def_config {
  return {
    api => [],
    default => undef
  };
}

# EVENT LISTENERS ##############################################################

sub _on_git_config_save {
  my $class = shift;
  my $git = shift;
  my $event = shift;
  my $config = shift;

  if ($config->{config}->{issue_tracker} ne $class->_name()) {
    return;
  }

  Daemon::printLabel("Gitlab");
  my $project_id = $class->_choose_project();
  system("git config memento.gitlab-project " . $project_id);
}

sub _on_git_flow_start {
  my $class = shift;

  if (!$class->_is_default()) {
    return;
  }

  my $subject = shift;
  my $event = shift;
  my $params = shift;
  my $storage = $class->_get_storage();

  if ($params->{issue}) {
    $storage->{issues}->{$params->{branch}} = {
      issue_id => $params->{issue}->{iid},
      gitlab_api_id => $class->_get_current_api_id()
    };
    $class->_save_storage($storage);
  }
}

sub _on_git_post_commit {
  my $class = shift;

  if (!$class->_is_default()) {
    return;
  }

  my $subject = shift;
  my $event = shift;
  my $params = shift;
  my $project_id = $class->_get_project_id();

  my $git = Memento::Tool->instantiate('git');
  my $issue = $git->_get_issue();

  if ($issue) {
    my $data = {
      id => $project_id,
      issue_id => $issue->{id},
      body => "*[memento]* " . $git->_get_pretty_commit_message()
    };
    $class->_call_api("projects/$project_id/issues/" . $issue->{id} . "/notes", $data, 'POST');
  }
}

# RULES ########################################################################

sub _conditions {
  return [
    {
      tool => 'gitlab',
      name => 'gitlab_check_default_api',
      callback => '_check_default_api',
      params => [
        {
          name => 'gitlab_api_id',
          label => 'Gitlab API ID'
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
  return ($class->_get_current_api_id() eq $params->{gitlab_api_id});
}

sub _actions {
  return [
    {
      tool => 'gitlab',
      name => 'gitlab_change_issue_status',
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
    my $project_id = $class->_get_project_id(0);
    my $status = $issue->{state};

    if (Daemon::prompt("Do you want to assign the issue to yourself?", 'yes', ['yes', 'no']) eq 'yes') {
      $data = {
        assignee_id => $user->{id}
      };
      $class->_call_api("projects/$project_id/issues/" . $issue->{id}, $data, 'PUT');
    }

    if (Daemon::prompt("Do you want to change the issue status [$status]?", 'yes', ['yes', 'no']) eq 'yes') {
      my %transitions = $class->_get_issue_transitions($issue);
      my $transition = Daemon::prompt("Choose a status", undef, [sort keys %transitions]);
      $data = {
        state_event => $transition
      };
      $class->_call_api("projects/$project_id/issues/" . $issue->{id}, $data, 'PUT');
    }

    if (Daemon::prompt("Do you want to add a comment to the issue?", 'no', ['yes', 'no']) eq 'yes') {
      my $filename = '/tmp/memento-gitlab-issue-comment';
      Daemon::write($filename, '', '1', '>');
      Daemon::open_default_editor($filename);
      my @content = Daemon::read($filename);
      unlink $filename;

      $data = {
        id => $project_id,
        issue_id => $issue->{id},
        body => "@content"
      };
      $class->_call_api("projects/$project_id/issues/" . $issue->{id} . "/notes", $data, 'POST');
    }

    print "\n";
    $class->_render_issue($class->_get_issue($issue->{iid}));
  }
}

# PRIVATE METHODS ##############################################################

sub _choose_project {
  my $class = shift;
  my %projects = $class->_get_projects();
  my $project = Daemon::prompt("Please select a Gitlab project", undef, [sort keys %projects]);
  return $projects{$project};
}

sub _get_project_id {
  my $class = shift;
  my $optional = shift || 1;

  my $project_id = `git config memento.gitlab-project`;
  chomp($project_id);

  if (!$project_id && !$optional) {
    die("Missing project id. Please configure Gitlab integration for this project.\n");
  }

  return $project_id;
}

sub _get_project {
  my $class = shift;
  my $project_id = shift or die "Missing project id to load";
  return $class->_call_api("projects/$project_id");
}

sub _get_projects {
  my $class = shift;
  my $data = $class->_call_api("projects", {'simple' => 1});
  my %projects;

  foreach my $project (@{$data}) {
    $projects{$project->{name_with_namespace}} = $project->{id};
  }

  return %projects;
}

sub _get_assignable_users {
  my $class = shift;
  my $data = $class->_call_api("users");
  my %users;

  foreach my $user (@{$data}) {
    $users{encode('utf8', $user->{name})} = $user->{id};
  }

  return %users;
}

sub _get_issue {
  my $class = shift;
  my $issue_id = shift or die "Missing issue id to load";
  my $project_id = $class->_get_project_id();

  if (!$project_id) {
    $project_id = $class->_choose_project();
  }

  my $issues = $class->_call_api("projects/$project_id/issues", {'iid' => $issue_id});
  return shift(@{$issues});
}

sub _get_issue_transitions {
  my $class = shift;
  my $issue = shift;
  my %transitions;

  my @States = qw(close reopen);

  foreach my $state (@States) {
    $transitions{$state} = $state;
  }

  return %transitions;
}

sub _get_current_user {
  my $class = shift;
  return $class->_call_api("user");
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

  die "Cannot find Gitlab API configurations saved with id $id\n";
}

sub _call_api {
  my $class = shift;
  my $path = shift;
  my $query = shift || {};
  my $method = shift || 'GET';
  my $config = $class->_get_config();

  if (!$config) {
    say "No Gitlab configuration has been found: creating a new configuration...";
    $class->config('add');
    die "\n";
  }

  my $api_id = $class->_get_current_api_id();
  if (!$api_id) {
    die "Please configure (switch to) a default Gitlab Api configuration\n";
  }

  my $settings = $class->_config_load($api_id);
  my $token = $settings->{token};
  my $gitlab_url = $settings->{url};
  my $uri = "$gitlab_url/api/v3/$path";

  my $response = Daemon::http_request($method, $uri, $query, {
    "Content-Type" => "application/json; charset=UTF-8",
    "PRIVATE-TOKEN" => "$token"
  });
  my $content = ($method eq 'GET') ? decode_json $response : $response;

  return $content;
}

sub _get_settings {
  my $class = shift;
  my $config = $class->_get_config();
  my $api_id = $class->_get_current_api_id();
  return $class->_config_load($api_id);
}

sub _render_issue {
  my $class = shift;
  my $issue = shift;
  my $full = shift;
  my $project = $class->_get_project($issue->{'project_id'});
  my $title = sprintf("[%s] #%s - %s", $project->{'name'}, $issue->{'iid'}, $issue->{'title'});
  my $bg_color = ($issue->{'state'} eq 'closed') ? "green" : (($issue->{'state'} eq 'opened') ? "yellow" : "blue");

  Daemon::printLabel($title, "bold white on_$bg_color");
  say sprintf("|- Status: %s", $issue->{'state'});
  say sprintf("|- Created by: %s on %s", $issue->{'author'}->{'name'}, $issue->{'created_at'});
  say sprintf("|- Assigned to: %s\n", $issue->{'assignee'}->{'name'}) if defined $issue->{'assignee'};

  if ($full) {
    Daemon::printLabel("Description");
    say encode('utf8', $issue->{'description'});
  }
}

sub _name {
  return 'gitlab';
}

sub _branch_pattern {
  return 'feature/:iid:-:title:';
}

sub _time_tracker_entry {
  my $class = shift;
  my $issue = shift;
  my $project = $class->_get_project($issue->{'project_id'});
  return  "#" . $issue->{'iid'} . " - " . $issue->{'title'} . "\nProject: " . $project->{'name'};
}

1;
