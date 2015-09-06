#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Memento/Command.pm";
our ($root);

package Memento::Tool::schema;

use feature 'say';
our @ISA = qw(Memento::Command);
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
  my $git = Memento::Tool->instantiate('git');

  chdir $root;
  my $sha = $git->_get_commit_sha();
  my $branch = $git->_get_current_branch();
  my $uri = "https://api.github.com/repos/bmeme/memento/branches/$branch";
  my $response = Daemon::http_request('GET', $uri, {}, [
    "Content-Type: application/json; charset=UTF-8",
    "Accept: application/vnd.github.v3+json",
    "User-Agent: memento"
  ]);

  my $content = decode_json $response;
  if ((defined $content->{commit}) && ($content->{commit}->{sha} ne $sha)) {
    print "\n";
    Daemon::printLabel("New memento version is now available!");

    my $details = [];
    my @updates = $git->_get_updates();

    foreach my $update (@updates) {
      $update =~ /^(\w+) (.*?)$/;
      push(@{$details}, {commit => $1, info => $2});
    }

    say Daemon::array2table("Memento Updates", $details);
    my $confirm = Daemon::prompt("Do you want to run code updates?", 'yes', ['yes', 'no']);

    if ($confirm eq 'yes') {
      my $remote = $git->_get_remote();
      system("git reset --hard HEAD");
      system("git pull $remote $branch");
      say Memento::splash();
      system("./install.pl");
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
        my $frequency = $config->{check_frequency} ? $config->{check_frequency} : 1;
        $config->{check_frequency} = Daemon::prompt("Please specify, in days, the update check frequency", $frequency);
      }

      $class->_save_config($config);
      say 'Memento schema configurations have been saved';
    }
    case 'list' {
      say Daemon::array2table("Schema Configurations", [$config]);
    }
  }
}

sub root {
  say Memento::Tool->root;
}

# OVERRIDDEN METHODS ###########################################################

sub _def_config {
  return {
    auto_check => 1,
    last_check => undef,
    check_frequency => 1
  };
}

# EVENT LISTENERS ##############################################################

sub _on_post_execution {
  my $class = Memento::Tool->instantiate('schema');
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
    $class->check();
  }
}

1;