#!/usr/bin/perl
require "$dir/Daemon.pm";
use feature 'say';
use JSON::PP;
use Data::Dumper;

package Memento;

sub redmine {
  my $key = $ENV{'MMNT_RM_KEY'};
  my $redmine_url = $ENV{'MMNT_RM_URL'};
  my $filename = 'response.json';
  `curl -k -H "Content-Type: application/json" -X GET -H "X-Redmine-API-Key: $key" $redmine_url/issues.json 2>&1> $filename`;
  my $data;
  if (open (my $json_stream, $filename))
  {
        local $/ = undef;
        my $json = JSON::PP->new;
        $data = $json->decode(<$json_stream>);
        close($json_stream);
  }
  print $data->{'total_count'};
}

sub status {
  say `git status -s`;
}

sub add {
  Daemon::root();
  `git add .`;
  status();
}

sub remove {
  $file = $_[1];
  if (!-e $file) {
    die("Trying to remove not existing file: $file");
  }
  Daemon::root();
  `git reset $file`;
  status();
}

sub ignore {
  $ignore = $_[1];
  Daemon::root();
  Daemon::write(".gitignore", $ignore, 1, '>>');
  say "$ignore added to .gitignore";
}
1;