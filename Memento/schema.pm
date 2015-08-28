#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Command.pm";
our ($root);

package Memento::schema;

use feature 'say';
our @ISA = qw(Command);
use strict; use warnings;
use Cwd;
use DateTime;
use DateTime::Format::Strptime;
use JSON::PP;
use POSIX qw(strftime);
use Switch;
use Data::Dumper;

sub check {
  my $class = shift;
  my $config = $class->_get_config();

  chdir $root;
  my $sha = `git rev-parse HEAD`;
  my $branch = `git rev-parse --abbrev-ref HEAD`;
  chomp($sha);
  chomp($branch);

  my $uri = "https://api.github.com/repos/bmeme/memento/branches/$branch";
  my $response = Daemon::http_request($uri, [
    "Content-Type: application/json; charset=UTF-8",
    "Accept: application/vnd.github.v3+json",
    "User-Agent: memento"
  ]);

  my $content = decode_json $response;
  if ($content->{commit}->{sha} ne $sha) {
    say "There is an available update:";
    my $excluded = ['comment_count', 'committer', 'tree', 'url'];
    say Daemon::array2table("Update details", [$content->{commit}->{commit}], {exclude => $excluded, colored => 1, full_nested => 1});
    my $confirm = Daemon::prompt("Do you want to run code updates?", undef, ['yes', 'no']);

    if ($confirm eq 'yes') {
      system("git reset --hard HEAD");
      system("git pull origin $branch");
    }
  }

  $config->{last_check} = strftime "%F", localtime;
  $class->_save_config($config);
}

sub config {
  my $class = shift;
  my $op = shift;
  my $config = $class->_get_config();

  if (!$op) {
    $op = Daemon::prompt("Choose an operation", undef, ['edit', 'list']);
  }

  switch ($op) {
    case 'edit' {
      my $conf;
      my $auto = Daemon::prompt("Do you want Memento to auto-check for updates once a day?", 'yes', ['yes', 'no']);
      $config->{auto_check} = ($auto eq 'yes') ? 1 : 0;

      if ($config->{auto_check}) {
        $config->{check_frequency} = Daemon::prompt("Please specify, in days, the update check frequency", 1)
      }

      $class->_save_config($config);
      say 'Memento schema configurations have been saved';
    }
    case 'list' {
      say Daemon::array2table("Schema Configurations", [$config]);
    }
  }
}

# OVERRIDDEN METHODS ###########################################################

sub _def_config {
  return {
    auto_check => 1,
    last_check => undef,
    check_frequency => 1
  };
}

sub _on_post_execution {
  my $class = Memento->instantiate('schema');
  my $config = $class->_get_config();

  if (!$config->{auto_check}) {
    return;
  }

  my $now = DateTime->now();
  my $last = $config->{last_check};
  my $check = 0;

  if (!$last) {
    $check = 1;
  }
  else {
    my $strp = DateTime::Format::Strptime->new(
      pattern => '%F'
    );
    $last = $strp->parse_datetime($last);

    if ($now->ymd ne $last->ymd) {
      my $duration = $now->subtract_datetime($last);
      $check = ($duration->in_units('days') >= $config->{check_frequency}) ? 1 : 0;
    }
  }

  if ($check) {
    system("memento schema check");
  }
}

1;