#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Memento/IssueTracker.pm";

package Memento::Tool::bitbucket;

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
      say "Please provide your Bitbucket info and remember that all values are mandatory";
      my $id = Daemon::prompt('Configuration id');
      my $username = Daemon::prompt('Bitbucket username or email');
      my $password = Daemon::prompt('Bitbucket password');

      my $conf = {
        id => $id,
        key => encode_base64("$username:$password")
      };

      my $is_default = (Daemon::prompt('Set this configuration as your default one?', 'yes', ['yes', 'no']) eq 'yes');

      push(@{$config->{api}}, $conf);
      if ($is_default) {
        $config->{default} = $conf->{id};
      }

      $class->_save_config($config);
      say 'Bitbucket API configurations have been saved';
    }
    case 'edit' {
      my $key = Daemon::prompt('Choose an api id', undef, $class->_get_api_ids());

      my $id = $config->{api}[$key]->{id};
      my $username = Daemon::prompt('Bitbucket username or email');
      my $password = Daemon::prompt('Bitbucket password');

      my $conf = {
        id => $id,
        key => encode_base64("$username:$password")
      };

      $config->{api}[$key] = $conf;
      $class->_save_config($config);
      say 'Bitbucket API configurations have been updated';

    }
    case 'delete' {
      if (scalar(@{$config->{api}}) < 1) {
        die "Bitbucket API configs not found.\n";
      }

      my $key = Daemon::prompt('Choose an api id to delete', undef, $class->_get_api_ids());
      delete $config->{api}[$key];
      $class->_save_config($config);
      say 'Bitbucket API configurations have been deleted';
    }
    case 'list' {
      say Daemon::array2table("Bitbucket Configurations", $config->{api});

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
        say "Bitbucket API switched to $id";
      }
      else {
        die "Bitbucket API id not found: $id\n";
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
    Daemon::open_default_browser($issue->{links}->{html}->{href});
  }
  else {
    $class->_render_issue($issue, 1);
  }
}

sub repositories {
  my $class = shift;
  my $config = $class->_get_config();
  my $username = $config->{'username'};
  my $data = $class->_call_api("repositories/$username", {'pagelen' => 50});

  my $repositories = [];
  foreach my $value (@{$data->{values}}) {
    my $repository = {
      has_issues => $value->{has_issues},
      description => $value->{description},
      scm => $value->{scm},
      language => $value->{language},
      full_name => $value->{full_name},
      owner => $value->{owner}->{display_name}
    };
    push(@{$repositories}, $repository);
  }

  say Daemon::array2table("Repositories", $repositories);
}

sub user {
  my $class = shift;
  my $user = $class->_get_current_user();
  my $users = [
    {
      username => $user->{username},
      display_name => $user->{display_name},
      created_on => $user->{created_on},
      website => $user->{website}
    }
  ];
  say Daemon::array2table("My Bitbucket Account", $users);
}

# OVERRIDDEN METHODS ###########################################################

sub _pre {
  my ($class) = @_;
  my $config = $class->_get_config();

  if ($config->{default}) {
    Daemon::printLabel("[Memento] » Bitbucket: " . $config->{default});
  }
}

sub _get_config {
  my $class = shift;
  my $config = $class->SUPER::_get_config();
  my $username = `git config memento.bitbucket-username`;
  my $repository = `git config memento.bitbucket-repository`;

  chomp($username);
  chomp($repository);
  $config->{username} = $username;
  $config->{repository} = $repository;

  return $config;
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

  my $repo_url = $git->_get_origin_url();
  if (!$repo_url) {
    Daemon::printLabel("Bitbucket");
    say "Bitbucket repository URL is missing. You need to specify it in order to proceed.";
    $repo_url = Daemon::prompt("Bitbucket repository URL");
  }

  my @paths = split /@/, $repo_url, 2;
  my $url = $paths[1];
  $url =~ s/bitbucket.org[:\/]?|\.git//g;
  my ($username, $repository) = split /\//, $url, 2;

  system("git config memento.bitbucket-username " . $username);
  system("git config memento.bitbucket-repository " . $repository);
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
  my $config = $class->_get_config();

  if ($params->{issue}) {
    $storage->{issues}->{$params->{branch}} = {
      issue_id => $params->{issue}->{id},
      bitbucket_api_id => $config->{default}
    };
    $class->_save_storage($storage);
  }
}

# PRIVATE METHODS ##############################################################

sub _get_issue {
  my $class = shift;
  my $issue_id = shift or die "Missing issue id to load";
  my $config = $class->_get_config();
  my $username = $config->{'username'};
  my $repository = $config->{'repository'};

  return $class->_call_api("repositories/$username/$repository/issues/$issue_id");
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
    say "No Bitbucket configuration has been found: creating a new configuration...";
    $class->config('add');
    die "\n";
  }

  if (!$config->{default}) {
    die "Please configure (switch to) a default Bitbucket Api configuration\n";
  }

  my $api_id = $config->{default};
  my $settings = $class->_config_load($api_id);
  my $key = $settings->{key};
  my $uri = "https://bitbucket.org/api/2.0/$path";

  my $response = Daemon::http_request($method, $uri, $query, {
    "Content-Type" => "application/json; charset=UTF-8",
    "Authorization" => "Basic $key"
  });
  my $content = ($method eq 'GET') ? decode_json $response : $response;

  return $content;
}

sub _get_settings {
  my $class = shift;
  my $config = $class->_get_config();
  my $api_id = $config->{default};
  return $class->_config_load($api_id);
}

sub _render_issue {
  my $class = shift;
  my $issue = shift;
  my $full = shift;
  my $title = sprintf("[%s] #%s - %s", $issue->{'repository'}->{'name'}, $issue->{'id'}, $issue->{'title'});
  my $bg_color = $class->_get_issue_color($issue);

  Daemon::printLabel($title, "bold white on_$bg_color");
  say sprintf("|- Status: %s", $issue->{'state'});
  say sprintf("|- Created by: %s on %s", $issue->{'reporter'}->{'display_name'}, $issue->{'created_on'});
  say sprintf("|- Assigned to: %s\n", $issue->{'assignee'}->{'display_name'}) if defined $issue->{'assignee'};

  if ($full) {
    Daemon::printLabel("Description");
    say encode('utf8', $issue->{'content'}->{'raw'});
  }
}

sub _get_issue_color {
  my $class = shift;
  my $issue = shift;
  my $states = {
    'new' => 'blue',
    'open' => 'yellow',
    'on hold' => 'cyan',
    'duplicate' => 'bright_red',
    'invalid' => 'red',
    'wontfix' => 'magenta',
    'resolved' => 'green',
    'closed' => 'bright_green'
  };
  return $states->{$issue->{state}};
}

sub _name {
  return 'bitbucket';
}

sub _branch_pattern {
  return ':id:-:title:';
}

sub _time_tracker_entry {
  my $class = shift;
  my $issue = shift;
  return  "#" . $issue->{'id'} . " - " . $issue->{'title'};
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

1;