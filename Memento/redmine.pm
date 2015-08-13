#!/usr/bin/perl
require "$root/Daemon.pm";
require "$root/Command.pm";

package Memento::redmine;
use feature 'say';
use JSON::PP;
our @ISA = qw(Command);
use strict; use warnings;
use URI;

my $filename = '/tmp/response.json';

sub issue {
  my $class = shift;
  my $issue = shift;
  my $data = $class->_call_api("issues/$issue");
  if (defined($data)) {
    $class->_render_issue($data->{'issue'}, 1);
  }

  if (Daemon::promptUser("\nDo you want to open this issue in your browser?", "y/n") eq "y") {
    my $uri = $ENV{'MMNT_RM_URL'} . "/issues/$issue";
    Daemon::open_default_browser($uri);
  }
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

  `curl -k -H "Content-Type: application/json" -X GET -H "X-Redmine-API-Key: $key" $uri 2>&1> $filename` or die("$!\n");

  my $data = undef;
  if ((-s $filename) && (open (my $json_stream, $filename))) {
    local $/ = undef;
    my $json = JSON::PP->new;
    $data = $json->decode(<$json_stream>);
    close($json_stream);
  }
  return $data;
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
    say $issue->{'description'};
  }
}

1;