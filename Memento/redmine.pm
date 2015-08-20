#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Command.pm";

package Memento::redmine;

use feature 'say';
use JSON::PP;
our @ISA = qw(Command);
use strict; use warnings;
use URI;
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
  my $op = shift || 'list';
  my $config = $class->_get_config();

  switch ($op) {
    case 'add' {
      my $conf;
      do {
        say "Please provide your Redmine info and remember that all values are mandatory";
        $conf = {
          id => Daemon::promptUser('Configuration id'),
          key => Daemon::promptUser('Redmine API Key'),
          url => Daemon::promptUser('Redmine URL')
        };
      }
      while (!$conf->{id} || !$conf->{key} || !$conf->{url});

      my $is_default = (Daemon::promptUser('Set this configuration as your default one?', 'y') eq 'y');

      push(@{$config->{api}}, $conf);
      if ($is_default) {
        $config->{default} = $conf->{id};
      }

      $class->_save_config($config);
      say 'Redmine API configurations have been saved';
    }
    case 'list' {
      say Daemon::array2table("Redmine Configurations", $config->{api});

      if ($config->{default}) {
        say "Default: $config->{default}";
      }
    }
    case 'delete' {
      my $id = $_[0] or die "Missing API id to delete\n";
      my $updated = 0;
      my $i = 0;
      for my $item (@{$config->{api}}) {
        if ($item->{id} eq $id) {
          delete $config->{api}[$i];
          $updated = 1;
        }
        $i++;
      }

      if ($updated) {
        $class->_save_config($config);
        say 'Redmine API configurations have been deleted';
      }
    }
    case 'switch' {
      my $id = $_[0] or die "Missing API id to switch\n";
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
    }
  }
}

sub issue {
  my $class = shift;
  my $id = shift || die "Missing issue id.\n";
  my $open = 0;

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
      $class->_render_issue($issue);
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

# OVERRIDDEN METHODS ###########################################################

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

# PRIVATE METHODS ##############################################################

sub _get_issue() {
  my $class = shift;
  my $id = shift or die "Missing issue id to load";
  my $data = $class->_call_api("issues/$id", {include => "attachments"});
  return $data->{issue};
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
  my $config = $class->_get_config();

  if (!$config) {
    say "No Redmine configuration has been found: creating a new configuration...";
    $class->config('add');
    die "\n";
  }

  if (!$config->{default}) {
    die "Please configure (switch to) a default Redmine Api configuration\n";
  }

  my $settings = $class->_config_load($config->{default});
  my $key = $settings->{key};
  my $redmine_url = $settings->{url};
  my $uri = URI->new("$redmine_url/$path.json");
  my $offset = '0';
  my $limit = '25';
  my $sort = '';
  my $page = 1;

  GetOptions(
    'offset=s' => \$offset,
    'limit=s' => \$limit,
    'sort=s' => \$sort,
    'page=s' => \$page
  ) or die 'Incorrect usage';

  if ($page) {
    $offset = $limit * ($page - 1);
  }

  my %querystring = %{$query};
  $querystring{'offset'} = $offset;
  $querystring{'limit'} = $limit;
  $querystring{'sort'} = $sort;
  $uri->query_form(%querystring);

  my $response = Daemon::http_request($uri, [
    "Content-Type: application/json; charset=UTF-8",
    "X-Redmine-API-Key: $key"
  ]);
  my $content = decode_json $response;

  if ($content->{'total_count'} && ($content->{'total_count'} > $content->{'limit'})) {
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
      my $direction = Daemon::promptUser('Prev or Next?', 'p/n');
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

        if ($command =~ /\-{2}page/) {
          $command =~ s/\-{2}page[=\"'\s]+(\w+)[\"'\s]?//;
        }
        system("$command --page $page");
      }
    }
  }
}

sub _render_issue {
  my $class = shift;
  my $issue = shift;
  my $title = sprintf("[%s] #%d - %s", $issue->{'project'}->{'name'}, $issue->{'id'}, $issue->{'subject'});
  my $bg_color = ($issue->{'done_ratio'} == 100) ? "green" : (($issue->{'done_ratio'} > 0) ? "yellow" : "red");

  Daemon::printLabel($title, "bold white on_$bg_color");
  say sprintf("|- %s: %s [%d/100]", $issue->{'tracker'}->{'name'}, $issue->{'status'}->{'name'}, $issue->{'done_ratio'});
  say sprintf("|- Created by: %s on %s", $issue->{'author'}->{'name'}, $issue->{'created_on'});
  say sprintf("|- Assigned to: %s\n", $issue->{'assigned_to'}->{'name'}) if defined $issue->{'assigned_to'};

  say Daemon::array2table("Attachments", $issue->{'attachments'}, {exclude => ['content_type', 'created_on', 'id']});
  Daemon::printLabel("Description");
  say encode('utf8', $issue->{'description'});
}

1;