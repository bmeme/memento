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
use Getopt::Long;
use Switch;
use MIME::Base64;
use Data::Dumper;

sub check {
  my $class = shift;
  my $config = $class->_get_config();
  my $force = 0;

  GetOptions(
    'force!' => \$force,
  ) or die 'Incorrect usage';


  if ($force) {
    $class->_on('schema_check', {});
    return;
  }

  if ($config->{auto_check}) {
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
      $class->_on('schema_check', {});
    }
  }
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

sub _pre {
  my ($class) = @_;

  if (!Daemon::in_array(['check', 'root'], $class->{command})) {
    $class->SUPER::_pre();
  }
}

# RULES ########################################################################

sub _events {
  return [
    {
      name => 'schema_check',
      arguments => []
    }
  ];
}

sub _on_schema_check {
  my $class = shift;
  my $config = $class->_get_config();
  my $git = Memento::Tool->instantiate('git');
  my $github_headers = {
    "Content-Type" => "application/json; charset=UTF-8",
    "Accept" => "application/vnd.github.v3+json",
    "User-Agent" => "memento"
  };

  chdir $root;

  my $sha = $git->_get_commit_sha();
  my $branch = $git->_get_current_branch();
  my $uri = "https://api.github.com/repos/bmeme/memento/branches/$branch";
  my $response = Daemon::http_request('GET', $uri, {}, $github_headers);

  my $content = decode_json $response;
  if ((defined $content->{commit}) && ($content->{commit}->{sha} ne $sha)) {
    print "\n";
    Daemon::printLabel("New memento version is now available!");

    my $details = [];
    my @updates = $git->_get_updates($root);

    foreach my $update (@updates) {
      $update =~ /^(\w+) (.*?)$/;
      push(@{$details}, {commit => $1, info => $2});
    }

    say Daemon::array2table("Memento Updates", $details);
    my $confirm = Daemon::prompt("Do you want to run code updates?", 'yes', ['yes', 'no']);

    if ($confirm eq 'yes') {
      # Get remote vendors info.
      my $full_install = 1;
      my $vendors_uri = 'https://api.github.com/search/code?q=repo:bmeme/memento+filename:vendors.pl';
      my $vendors_response = Daemon::http_request('GET', $vendors_uri, {}, $github_headers);
      my $vendors_content = decode_json $vendors_response;

      # If vendors file exists, let's check it's content.
      if (($vendors_content->{total_count} > 0)) {
        my $git_url = $vendors_content->{items}[0]->{git_url};
        my $file_response = Daemon::http_request('GET', $git_url, {}, $github_headers);
        $file_response = decode_json $file_response;

        # Remove carriage returns for later comparison with local file.
        my $vendors_file_content = $file_response->{content};
        $vendors_file_content =~ s/[\r\n]+//gm;

        # Read local vendors file content.
        local $/;
        open(FILE, './vendors.pl') or die "Can't read file 'filename' [$!]\n";
        my $local_vendors = <FILE>;
        close (FILE);

        # Encode in base 64 like the remote one and remove carriage returns.
        my $local_vendors_file_content = encode_base64($local_vendors);
        $local_vendors_file_content =~ s/[\r\n]+//gm;

        # No need to rerun the full installation if there are no vendor changes.
        if ($local_vendors_file_content eq $vendors_file_content){
          $full_install = 0;
        }
      }

      my $remote = $git->_get_remote();
      Daemon::system("git reset --hard HEAD");
      Daemon::system("git pull $remote $branch");

      say Memento::splash();

      if ($full_install) {
        Daemon::system("./install.pl");
      }
    }
  }

  $config->{last_check} = strftime "%F", localtime;
  $class->_save_config($config);
}

1;