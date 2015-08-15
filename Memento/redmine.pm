#!/Applications/MAMP/Library/bin/perl
require "$root/Daemon.pm";
require "$root/Command.pm";

package Memento::redmine;

use feature 'say';
use JSON::PP;
our @ISA = qw(Command);
use strict; use warnings;
use URI;
use Data::Dumper;
use Getopt::Long;
use Text::Aligner;
use Text::Table;
use POSIX;

our (%pager);

sub issue {
  my $class = shift;
  my $issue = shift || die "Missing issue number.\n";
  my $open = 0;

  GetOptions(
    'open!' => \$open
  ) or die 'Incorrect usage';

  if ($open) {
    my $uri = $ENV{'MMNT_RM_URL'} . "/issues/$issue";
    Daemon::open_default_browser($uri);
  }
  else {
    my $data = $class->_call_api("issues/$issue", {include => "attachments"});
    if (defined($data)) {
      $class->_render_issue($data->{'issue'}, 1);
    }
  }
}

sub queries {
  my $class = shift;
  my $data = $class->_call_api("queries");
  Daemon::json2table("Queries", $data->{'queries'});
}

sub query {
  my $class = shift;
  my $query_id = shift;
  $query_id = ($query_id && !($query_id =~ /^\-{2}/)) ? {query_id => $query_id} : {};
  my $data = $class->_call_api("issues", $query_id);
  Daemon::json2table("Query", $data->{'issues'}, ['description', 'created_on']);
}

sub projects {
  my $class = shift;
  my $data = $class->_call_api("projects");
  Daemon::json2table("Projects", $data->{'projects'}, ['description', 'created_on', 'updated_on']);
}

# OVERRIDDEN METHODS ###########################################################

sub _done {
  my $class = shift;
  $class->_render_pager();
}

# PRIVATE METHODS ##############################################################

sub _call_api {
  my $class = shift;
  my $path = shift;
  my $query = shift || {};

  my $key = $ENV{'MMNT_RM_KEY'} or die "Missing Redmine API Key. Please export it as an env var MMNT_RM_KEY.";
  my $redmine_url = $ENV{'MMNT_RM_URL'} or die "Missing Redmine URL. Please export it as an env var MMNT_RM_URL.";
  my $uri = URI->new("$redmine_url/$path.json");
  my $offset = '0';
  my $limit = '25';

  GetOptions(
    'offset=s' => \$offset,
    'limit=s' => \$limit
  ) or die 'Incorrect usage';

  my %querystring = %{$query};
  $querystring{'offset'} = $offset;
  $querystring{'limit'} = $limit;

  $uri->query_form(%querystring);

  `curl -k -H "Content-Type: application/json" -X GET -H "X-Redmine-API-Key: $key" "$uri" 2>&1> $class->{storage}` or die("$!\n");
  my $content = Daemon::json_decode_file($class->{storage});

  if ($content->{'total_count'} && ($content->{'total_count'} > $content->{'limit'})) {
    %pager = (
      'current' => ($content->{'offset'} > $content->{'limit'}) ? floor($content->{'offset'} / $content->{'limit'}): 1,
      'total' => ceil($content->{'total_count'} / $content->{'limit'}),
      'quantity' => $content->{'limit'},
      'total_items' => $content->{'total_count'},
      'offset' => $content->{'offset'}
    );
  }

  return $content;
};

sub _render_pager {
  if (%pager) {
    say "Page $pager{current} of $pager{total} [$pager{offset}/$pager{total_items}]";
  }
}

sub _render_issue {
  my $class = shift;
  my $issue = shift;
  my $full = shift;

  my $title = sprintf("[%s] #%d - %s", $issue->{'project'}->{'name'}, $issue->{'id'}, $issue->{'subject'});
  my $bg_color = ($issue->{'done_ratio'} == 100) ? "green" : (($issue->{'done_ratio'} > 0) ? "yellow" : "red");
  Daemon::printLabel($title, "white on_$bg_color");
  say sprintf("|- %s: %s [%d/100]", $issue->{'tracker'}->{'name'}, $issue->{'status'}->{'name'}, $issue->{'done_ratio'});

  if ($full) {
    say sprintf("|- Created by: %s on %s", $issue->{'author'}->{'name'}, $issue->{'created_on'});
    say sprintf("|- Assigned to: %s\n", $issue->{'assigned_to'}->{'name'});

    if (@{$issue->{'attachments'}}) {
      Daemon::json2table("Attachments", $issue->{'attachments'}, ['content_type', 'created_on', 'id']);
    }

    Daemon::printLabel("Description");
    say $issue->{'description'};
  }
}

1;