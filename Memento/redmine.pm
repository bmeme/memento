#!/usr/bin/perl
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

my $spool = '/tmp/mmnt_rm_spool.json';

sub issue {
  my $class = shift;
  my $issue = shift;
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

  #(Daemon::promptUser("\nDo you want to open this issue in your browser?", "y/n") eq "y")
}

sub query {
  my $class = shift;
  my $query_id = shift;
  my $data = $class->_call_api("issues", {query_id => $query_id});

  for (my $i=0; $i<$data->{'total_count'}; $i++) {
    my $issue = $data->{'issues'}[$i];
    $class->_render_issue($issue, 0);
    print "\n";
  }
}

sub projects {
  my $class = shift;
  my $return = shift;
  my $fetch = 0;
  my $projects_file = "/tmp/mmnt_rm_prj.json";
  my $projects;

  GetOptions(
    'fetch!' => \$fetch
  ) or die 'Incorrect usage';

  if ((!-f $projects_file) || $fetch) {
    $projects = $class->_call_api("projects");
    my $content = encode_json $projects;
    Daemon::write($projects_file, $content, 1, '>');
  }
  else {
    $projects = Daemon::json_decode_file($projects_file);
  }

  if ($return) {
    return $projects;
  }
  else {
    for my $project (@{$projects->{'projects'}}) {
        say sprintf("| [%s] #%d", $project->{'name'}, $project->{'id'});
        say sprintf("| - Identifier: %s\n", $project->{'identifier'});
    }
  }
}

# PRIVATE METHODS ##############################################################

sub _call_api {
  my $class = shift;
  my $path = shift;
  my $query = shift || {};
  my $key = $ENV{'MMNT_RM_KEY'} or die "Missing Redmine API Key. Please export it as an env var MMNT_RM_KEY.";
  my $redmine_url = $ENV{'MMNT_RM_URL'} or die "Missing Redmine URL. Please export it as an env var MMNT_RM_URL.";
  my $uri = URI->new("$redmine_url/$path.json");

  if (keys $query) {
    $uri->query_form($query);
  }

  `curl -k -H "Content-Type: application/json" -X GET -H "X-Redmine-API-Key: $key" $uri 2>&1> $spool` or die("$!\n");
  return Daemon::json_decode_file($spool);
};

sub _render_issue {
  my $class = shift;
  my $issue = shift;
  my $full = shift;

  say sprintf("| [%s] #%d - %s", $issue->{'project'}->{'name'}, $issue->{'id'}, $issue->{'subject'});
  say sprintf("| - %s: %s [%d/100]", $issue->{'tracker'}->{'name'}, $issue->{'status'}->{'name'}, $issue->{'done_ratio'});

  if ($full) {
    say sprintf("| - Created by: %s on %s", $issue->{'author'}->{'name'}, $issue->{'created_on'});
    say sprintf("| - Assigned to: %s\n", $issue->{'assigned_to'}->{'name'});

    my @rows = ();
    for my $item (@{$issue->{'attachments'}}) {
        my $name = $item->{description} ? $item->{description} : $item->{filename};
        push(@rows, [($name, $item->{content_url})]);
    }

    say "##### Description #####";
    say $issue->{'description'};
    say "#######################";
  }
}

1;