#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Memento/IssueTracker.pm";

package Memento::Tool::jira;

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
use JIRA::REST;
use Data::Dumper;

our ($jira);

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
      say "Please provide your Jira info and remember that all values are mandatory";
      my $id = Daemon::prompt('Configuration id');
      my $credentials = $class->_get_credentials();
      my $username = $credentials->{username};
      my $password = $credentials->{password};
      my $url = Daemon::prompt('Jira URL');

      my $conf = {
        id => $id,
        key => encode_base64("$username:$password"),
        url => $url,
        type => $credentials->{type}
      };

      my $is_default = (Daemon::prompt('Set this configuration as your default one?', 'yes', ['yes', 'no']) eq 'yes');

      push(@{$config->{api}}, $conf);
      if ($is_default) {
        $config->{default} = $conf->{id};
      }

      $class->_save_config($config);
      say 'Jira API configurations have been saved';
    }
    case 'edit' {
      my $key = Daemon::prompt('Choose an api id', undef, $class->_get_api_ids());

      my $id = $config->{api}[$key]->{id};
      my $credentials = $class->_get_credentials();
      my $username = $credentials->{username};
      my $password = $credentials->{password};
      my $url = Daemon::prompt('Jira URL', $config->{api}[$key]->{url});

      my $conf = {
        id => $id,
        key => encode_base64("$username:$password"),
        url => $url,
        type => $credentials->{type}
      };

      $config->{api}[$key] = $conf;
      $class->_save_config($config);
      say 'Jira API configurations have been updated';

    }
    case 'delete' {
      if (scalar(@{$config->{api}}) < 1) {
        die "Jira API configs not found.\n";
      }

      my $key = Daemon::prompt('Choose an api id to delete', undef, $class->_get_api_ids());
      delete $config->{api}[$key];
      $class->_save_config($config);
      say 'Jira API configurations have been deleted';
    }
    case 'list' {
      say Daemon::array2table("Jira Configurations", $config->{api});

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
        say "Jira API switched to $id";
      }
      else {
        die "Jira API id not found: $id\n";
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

  if ($open) {
    my $settings = $class->_config_load($class->_get_current_api_id());
    my $uri = $settings->{url} . "/browse/$id";
    Daemon::open_default_browser($uri);
  }
  else {
    my $issue = $class->_get_issue($id);
    $class->_render_issue($issue, 1);
  }
}

sub projects {
  my $class = shift;
  my $data = $class->_call_api("project");
  say Daemon::array2table("Projects", $data, {exclude => ['avatarUrls', 'expand', 'projectCategory', 'projectTypeKey', 'self']});
}

sub user {
  my $class = shift;
  my $user = $class->_get_current_user();
  say Daemon::array2table("My Jira Account", [$user], {exclude => ['avatarUrls', 'expand', 'applicationRoles', 'timezone']});
}

sub search {
  my $class = shift;
  my $options = {
    resolution => 0,
    project => 0,
    type => 0,
    status => 0,
    assignee => 0
  };
  my @jql = ();

  GetOptions(
    'resolution=s' => \$options->{resolution},
    'project=s' => \$options->{project},
    'type=s' => \$options->{type},
    'status=s' => \$options->{status},
    'assignee=s' => \$options->{assignee}
  ) or die 'Incorrect usage';

  for my $key (keys %{$options}) {
    if ($options->{$key}) {
      push(@jql, "$key=$options->{$key}");
    }
  }

  if (!@jql) {
    say "Please execute 'memento jira search' with the following options:";
    Daemon::print_list([keys %{$options}]);
    die("\n");
  }

  my $query = {jql => join(' AND ', @jql)};
  my $data = $class->_call_api("search", $query);
  if (!$data->{issues}) {
    say "No results found for this search";
    return;
  }

  my $issues = [];
  foreach my $issue (@{$data->{issues}}) {
    push(@{$issues}, $class->_build_search_result($issue));
  }

  say Daemon::array2table("Issues", $issues);
}

# OVERRIDDEN METHODS ###########################################################

sub _pre {
  my ($class) = @_;
  my $api_id = $class->_get_current_api_id();

  if ($api_id) {
    Daemon::printLabel("[Memento] » Jira: " . $api_id);
  }
}

sub _def_config {
  return {
    api => [],
    default => undef
  };
}

sub _fix_branch_prefix {
  my $class = shift;
  my $prefix = shift;
  my $issue = shift;
  my $type = lc $issue->{fields}->{issuetype}->{name};

  if ($issue->{fields}->{issuetype}->{subtask}) {
    my $parent_type = lc $issue->{fields}->{parent}->{fields}->{issuetype}->{name};
    my $parent_key = $issue->{fields}->{parent}->{key};

    # since whitespaces can be used, converts anything different from the pattern.
    $parent_type =~ s/[^\w\-]+/-/g;

    $prefix = "$parent_type/$parent_key/$type";
  }

  return $prefix;
}

sub _fix_branch_name {
  my $class = shift;
  my $branch = shift;
  my $issue = shift;
  my $key = $issue->{key};
  my $key_lc = lc $issue->{key};

  $branch =~ s/$key_lc/$key/;
  return $branch;
}

sub _get_credentials {
  my $class = shift;
  my $type = Daemon::prompt('Choose an authentication method', undef, ['Basic Authentication', 'Api token']);
  my $username = "";
  my $password = "";

  if ($type eq 'Api token') {
    $type = 'token';
    $username = Daemon::prompt('Jira account email');
    $password = Daemon::prompt('Jira API token (https://id.atlassian.com/manage/api-tokens)');
  }
  else {
    $type = 'basic';
    $username = Daemon::prompt('Jira username');
    $password = Daemon::prompt('Jira password');
  }

  return {
    type => $type,
    username => $username,
    password => $password
  }
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

  if ($params->{issue}) {
    $storage->{issues}->{$params->{branch}} = {
      issue_id => $params->{issue}->{id},
      jira_api_id => $class->_get_current_api_id()
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

  my $git = Memento::Tool->instantiate('git');
  my $issue = $git->_get_issue();

  if ($issue) {
    my $data = {
      body => "*[memento]* " . $git->_get_pretty_commit_message()
    };
    $class->_call_api("issue/" . $issue->{key} . "/comment", $data, 'POST');
  }
}

sub _on_schema_check {
  my $class = shift;
  my $config = $class->_get_config();
  if (!$config->{default}) {
    return;
  }

  my $settings = $class->_get_settings();
  my $username = $settings->{username};
  my $query = {jql => "status not in (\"Closed\", \"Done\", \"Resolved\") AND assignee='$username'"};
  my $data = $class->_call_api("search", $query);

  if (!$data->{issues}) {
    return;
  }

  my $issues = [];
  foreach my $issue (@{$data->{issues}}) {
    push(@{$issues}, $class->_build_search_result($issue));
  }

  Daemon::printLabel("[Memento] » Jira");
  say Daemon::array2table("Your open issues", $issues);
}

# RULES ########################################################################

sub _conditions {
  return [
    {
      tool => 'jira',
      name => 'jira_check_default_api',
      callback => '_check_default_api',
      params => [
        {
          name => 'jira_api_id',
          label => 'Jira API ID'
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
  return ($class->_get_current_api_id() eq $params->{jira_api_id});
}

sub _actions {
  return [
    {
      tool => 'jira',
      name => 'jira_change_issue_status',
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
      my %assignees = $class->_get_assignable_users($issue->{key});
      my $assignee = Daemon::prompt("Choose an assignee", undef, [sort keys %assignees]);
      $data = {
        accountId => $assignees{$assignee}
      };
      $class->_call_api("issue/" . $issue->{id} . "/assignee", $data, 'PUT');
    }

    if (Daemon::prompt("Do you want to change the issue status?", 'yes', ['yes', 'no']) eq 'yes') {
      my %transitions = $class->_get_issue_transitions($issue);
      my $transition = Daemon::prompt("Choose a status", undef, [sort keys %transitions]);
      $data = {
        transition => {
          id => $transitions{$transition}
        }
      };
      $class->_call_api("issue/" . $issue->{id} . "/transitions", $data, 'POST');
    }

    if (Daemon::prompt("Do you want to add a comment to the issue?", 'no', ['yes', 'no']) eq 'yes') {
      my $filename = '/tmp/memento-jira-issue-comment';
      Daemon::write($filename, '', '1', '>');
      Daemon::open_default_editor($filename);
      my @content = Daemon::read($filename);
      unlink $filename;

      $data = {
        body => "@content"
      };
      $class->_call_api("issue/" . $issue->{id} . "/comment", $data, 'POST');
    }

    print "\n";
    $class->_render_issue($class->_get_issue($issue->{id}));
  }
}

# PRIVATE METHODS ##############################################################

sub _get_assignable_users {
  my $class = shift;
  my $issue_key = shift;
  my $data = $class->_call_api("user/assignable/search", {'issueKey' => $issue_key});
  my %users;

  foreach my $user (@{$data}) {
    $users{encode('utf8', $user->{displayName})} = $user->{accountId};
  }

  return %users;
}

sub _get_issue {
  my $class = shift;
  my $id = shift or die "Missing issue id to load";
  return $class->_call_api("issue/$id");
}

sub _get_issue_transitions {
  my $class = shift;
  my $issue = shift;
  my $data = $class->_call_api("issue/$issue->{id}/transitions");
  my %transitions;

  foreach my $transition (@{$data->{transitions}}) {
    $transitions{$transition->{to}->{name}} = $transition->{id};
  }

  return %transitions;
}

sub _get_current_user {
  my $class = shift;
  return $class->_call_api("myself");
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

  die "Cannot find Jira API configurations saved with id $id\n";
}

sub _call_api {
  my $class = shift;
  my $path = shift;
  my $query = shift || undef;
  my $method = shift || 'GET';
  my $values = undef;
  my $config = $class->_get_config();

  if (!$config) {
    say "No Jira configuration has been found: creating a new configuration...";
    $class->config('add');
    die "\n";
  }

  if (!$config->{default}) {
    die "Please configure (switch to) a default Jira Api configuration\n";
  }

  if ($method ne 'GET') {
    $values = $query;
    $query = undef;
  }

  my $client = $class->_get_client();
  return $client->$method("/$path", $query, $values);
}

sub _get_settings {
  my $class = shift;
  my $config = $class->_get_config();
  my $api_id = $class->_get_current_api_id();
  my $settings = $class->_config_load($api_id);
  my ($username, $password) = split(':', decode_base64($settings->{key}));
  $settings->{username} = $username;
  $settings->{password} = $password;
  return $settings;
}

sub _get_client {
  my $class = shift;
  if ($jira) {
    return $jira;
  }

  my $settings = $class->_get_settings();
  $jira = JIRA::REST->new($settings->{url}, $settings->{username}, $settings->{password});
  return $jira;
}

sub _render_issue {
  my $class = shift;
  my $issue = shift;
  my $full = shift;
  my $fields = $issue->{'fields'};
  my $title = sprintf("[%s] #%s - %s", $fields->{'project'}->{'name'}, $issue->{'key'}, $fields->{'summary'});
  my @color = split('-', $fields->{'status'}->{'statusCategory'}->{'colorName'});
  my $bg_color = $class->_get_issue_color($color[-1]);

  Daemon::printLabel($title, "bold white on_$bg_color");
  say sprintf("|- %s: %s", encode('utf8', $fields->{'issuetype'}->{'name'}), $fields->{'status'}->{'name'});
  say sprintf("|- Created by: %s on %s", $fields->{'creator'}->{'displayName'}, $fields->{'created'});
  say sprintf("|- Assigned to: %s\n", $fields->{'assignee'}->{'displayName'}) if defined $fields->{'assignee'};

  if ($full) {
    my $attachments = Daemon::array2table("Attachments", $fields->{'attachment'}, {exclude => ['self', 'author', 'created', 'mimeType']});
    if ($attachments) {
      say $attachments;
    }

    Daemon::printLabel("Description");
    say encode('utf8', $fields->{'description'});
  }
}

sub _get_issue_color {
  my $class = shift;
  my $color = shift;
  my $basic_colors = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white'];

  if (!Daemon::in_array($basic_colors, $color)) {
    $color =~ s/gray/grey/g;
    $color = $color . "10";
  }

  return $color;
}

sub _name {
  return 'jira';
}

sub _branch_pattern {
  return ':fields-issuetype-name:/:key:-:fields-summary:';
}

sub _time_tracker_entry {
  my $class = shift;
  my $issue = shift;
  return "#" . $issue->{'key'} . " - " . $issue->{'fields'}->{'summary'} . "\nProject: " . $issue->{'fields'}->{'project'}->{'name'};
}

sub _build_search_result {
  my $class = shift;
  my $issue = shift;
  my $fields = $issue->{fields};
  return {
    'id|key' => "$issue->{id}|$issue->{key}",
    summary => $fields->{summary},
    assignee => $fields->{assignee}->{name},
    creator => $fields->{creator}->{name},
    type => $fields->{issuetype}->{name},
    project => $fields->{project}->{name},
    status => $fields->{status}->{name},
    resolution => $fields->{resolution}->{name},
    priority => $fields->{priority}->{name}
  };
}

1;
