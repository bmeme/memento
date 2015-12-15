#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Memento/IssueTracker.pm";

package Memento::Tool::redmine;

use feature 'say';
use JSON::PP;
our @ISA = qw(Memento::IssueTracker);
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
      say "Please provide your Redmine info and remember that all values are mandatory";
      $conf = {
        id => Daemon::prompt('Configuration id'),
        key => Daemon::prompt('Redmine API Key'),
        url => Daemon::prompt('Redmine URL')
      };

      my $is_default = (Daemon::prompt('Set this configuration as your default one?', 'yes', ['yes', 'no']) eq 'yes');

      push(@{$config->{api}}, $conf);
      if ($is_default) {
        $config->{default} = $conf->{id};
      }

      $class->_save_config($config);
      say 'Redmine API configurations have been saved';
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
        key => Daemon::prompt('Redmine API Key', $config->{api}[$key]->{key}),
        url => Daemon::prompt('Redmine URL', $config->{api}[$key]->{url})
      };

      $config->{api}[$key] = $conf;
      $class->_save_config($config);
      say 'Redmine API configurations have been updated';

    }
    case 'delete' {
      if (scalar(@{$config->{api}}) < 1) {
        die "Redmine API configs not found.\n";
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

      say 'Redmine API configurations have been deleted';
    }
    case 'list' {
      say Daemon::array2table("Redmine Configurations", $config->{api});

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
        say "Redmine API switched to $id";
      }
      else {
        die "Redmine API id not found: $id\n";
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
    my $config = $class->_get_config();
    my $settings = $class->_config_load($config->{default});
    my $uri = $settings->{url} . "/issues/$id";
    Daemon::open_default_browser($uri);
  }
  else {
    my $issue = $class->_get_issue($id);
    if (defined($issue)) {
      $class->_render_issue($issue, 1);
    }
  }
}

sub queries {
  my $class = shift;
  my $data = $class->_call_api("queries");
  say Daemon::array2table("Queries", $data->{'queries'});
}

sub query {
  my $class = shift;
  my $query_id = shift;
  $query_id = ($query_id && !($query_id =~ /^\-{2}/)) ? {query_id => $query_id} : {};
  my $data = $class->_call_api("issues", $query_id);
  say Daemon::array2table("Query", $data->{'issues'}, {exclude => ['description', 'created_on', 'custom_fields']});
}

sub projects {
  my $class = shift;
  my $data = $class->_call_api("projects");
  say Daemon::array2table("Projects", $data->{'projects'}, {exclude => ['description', 'created_on', 'updated_on', 'custom_fields']});
}

sub user {
  my $class = shift;
  my $user = $class->_get_current_user();
  say Daemon::array2table("My Redmine Account", [$user]);
}

# OVERRIDDEN METHODS ###########################################################

sub _pre {
  my ($class) = @_;
  my $config = $class->_get_config();

  if ($config->{default}) {
    Daemon::printLabel($config->{default});
  }
}

sub _done {
  my $class = shift;
  $class->_render_pager();
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

  if ($params->{issue}) {
    $storage->{issues}->{$params->{branch}} = {
      issue_id => $params->{issue}->{id},
      redmine_api_id => $config->{default}
    };
    $class->_save_storage($storage);
  }
}

sub _on_git_post_commit {
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

sub _on_schema_check {
  my $class = shift;
  my $query = {assigned_to_id => "me", set_filter => 1, sort => "priority:desc,updated_on:desc"};
  my $data = $class->_call_api("issues", $query);

  print "\n";
  Daemon::printLabel("[Memento] - Redmine");
  say "This is just a reminder from your issue tracker. Don't ever forget to work on your open issues.";
  say Daemon::array2table("Your open issues", $data->{'issues'}, {exclude => ['description', 'created_on', 'custom_fields']});
}

# RULES ########################################################################

sub _conditions {
  return [
    {
      tool => 'redmine',
      name => 'redmine_check_default_api',
      callback => '_check_default_api',
      params => [
        {
          name => 'redmine_api_id',
          label => 'Redmine API ID'
        }
      ]
    }
  ];
}

sub _check_default_api {
  my $class = shift;
  my $params = shift;
  my $config = $class->_get_config();
  return ($config->{default} eq $params->{redmine_api_id});
}

sub _actions {
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

sub _change_issue_status {
  my $class = shift;
  my $arguments = shift;
  my $params = shift;

  if ($arguments->{issue}) {
    my $issue = $arguments->{issue};
    my $statuses = $class->_get_issue_statuses(1);

    foreach my $status (@{$statuses}) {
      if ($status->{name} eq $params->{status}) {
        $params->{status} = $status->{id};
      }
    }

    my $user = $class->_get_current_user();

    if (Daemon::prompt("Do you want to change the issue assignee?", 'no', ['yes', 'no']) eq 'yes') {
      my $project_id = $issue->{project}->{id};
      my $memberships = $class->_get_project_memberships($project_id);
      my %assignees;
      foreach my $membership (@{$memberships}) {
        my $member = defined $membership->{group} ? $membership->{group} : $membership->{user};
        $assignees{$member->{name}} = $member;
      }
      my $assignee = Daemon::prompt("Choose an assignee", undef, [keys %assignees]);
      $user = $assignees{$assignee};
    }

    my $data = {
      issue => {
        assigned_to_id => $user->{id},
        status_id => $params->{status},
        done_ratio => $params->{done_ratio}
      }
    };

    if (Daemon::prompt("Do you want to add a comment to the issue?", 'no', ['yes', 'no']) eq 'yes') {
      my $filename = '/tmp/memento-redmine-issue-comment';
      Daemon::write($filename, '', '1', '>');
      Daemon::open_default_editor($filename);
      my @content = Daemon::read($filename);
      unlink $filename;
      $data->{issue}->{notes} = "@content";
    }
    $class->_call_api("issues/" . $issue->{id}, $data, 'PUT');

    print "\n";
    $class->_render_issue($class->_get_issue($issue->{id}));
  }
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
  my $data = $class->_call_api("users/current");
  return $data->{'user'};
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

  die "Cannot find Redmine API configurations saved with id $id\n";
}

sub _call_api {
  my $class = shift;
  my $path = shift;
  my $query = shift || {};
  my $method = shift || 'GET';
  my $config = $class->_get_config();

  if (!$config) {
    say "No Redmine configuration has been found: creating a new configuration...";
    $class->config('add');
    die "\n";
  }

  if (!$config->{default}) {
    die "Please configure (switch to) a default Redmine Api configuration\n";
  }

  my $api_id = $config->{default};
  my $settings = $class->_config_load($api_id);
  my $key = $settings->{key};
  my $redmine_url = $settings->{url};
  my $uri = "$redmine_url/$path.json";
  my $page = 1;

  if ($method eq 'GET') {
    my $offset = '0';
    my $limit = defined $query->{limit} ? $query->{limit} : '25';
    my $sort = '';

    GetOptions(
      'api-id=s' => \$api_id,
      'offset=s' => \$offset,
      'limit=s' => \$limit,
      'sort=s' => \$sort,
      'page=s' => \$page
    ) or die 'Incorrect usage';

    if ($page) {
      $offset = $limit * ($page - 1);
    }

    $query->{offset} = $offset;
    $query->{limit} = $limit;
    $query->{sort} = $sort;
  }

  my $response = Daemon::http_request($method, $uri, $query, [
    "Content-Type: application/json; charset=UTF-8",
    "X-Redmine-API-Key: $key"
  ]);
  my $content = ($method eq 'GET') ? decode_json $response : $response;

  if (($method eq 'GET') && $content->{'total_count'} && ($content->{'total_count'} > $content->{'limit'})) {
    my $current = ($content->{'offset'} > $content->{'limit'}) ? floor($content->{'offset'} / $content->{'limit'}): $page;
    my $items = $content->{'limit'} * $current;
    %pager = (
      'current' => $current,
      'total' => ceil($content->{'total_count'} / $content->{'limit'}),
      'quantity' => $content->{'limit'},
      'items' => $items < $content->{'total_count'} ? $items : $content->{'total_count'},
      'total_items' => $content->{'total_count'},
      'offset' => $content->{'offset'},
      'class' => $class
    );
  }

  return $content;
};

sub _render_pager {
  if (%pager) {
    say "Page $pager{current} of $pager{total} [$pager{items}/$pager{total_items}]";

    if ($pager{total} > 1) {
      my $direction = Daemon::prompt('Prev or Next?', 'p/n');
      my $page = $pager{'current'};
      switch ($direction) {
        case 'n' {
          $page = ($pager{'current'} < $pager{'total'}) ? $page + 1 : $page;
        }
        case 'p' {
          $page = ($pager{'current'} > 1) ? $page - 1 : $page;
        }
      }

      if ($page != $pager{'current'}) {
        my $command = `memento history last`;
        chomp($command);

        # handle --limit
        my $limit = '';
        if ($command =~ /\-{2}limit[=\"'\s]?(\w+)?[\"'\s]?/) {
          $limit = " --limit $1";
          $command =~ s/\-{2}limit[=\"'\s]?(\w+)?[\"'\s]?//;
        }

        # unset --offset.
        $command =~ s/\-{2}offset[=\"'\s]?(\w+)?[\"'\s]?//;

        # unset --page.
        if ($command =~ /\-{2}page/) {
          $command =~ s/\-{2}page[=\"'\s]?(\w+)?[\"'\s]?//;
        }

        system("$command --page $page $limit");
      }
    }
  }
}

sub _render_issue {
  my $class = shift;
  my $issue = shift;
  my $full = shift;
  my $title = sprintf("[%s] #%d - %s", $issue->{'project'}->{'name'}, $issue->{'id'}, $issue->{'subject'});
  my $bg_color = ($issue->{'done_ratio'} == 100) ? "green" : (($issue->{'done_ratio'} > 0) ? "yellow" : "red");

  Daemon::printLabel($title, "bold white on_$bg_color");
  say sprintf("|- %s: %s [%d/100]", $issue->{'tracker'}->{'name'}, $issue->{'status'}->{'name'}, $issue->{'done_ratio'});
  say sprintf("|- Created by: %s on %s", $issue->{'author'}->{'name'}, $issue->{'created_on'});
  say sprintf("|- Assigned to: %s\n", $issue->{'assigned_to'}->{'name'}) if defined $issue->{'assigned_to'};

  if ($full) {
    my $attachments = Daemon::array2table("Attachments", $issue->{'attachments'}, {exclude => ['content_type', 'created_on', 'id']});
    if ($attachments) {
      say $attachments;
    }

    Daemon::printLabel("Description");
    say encode('utf8', $issue->{'description'});
  }
}

1;