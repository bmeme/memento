#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Command.pm";

package Memento::git;

use feature 'say';
our @ISA = qw(Command);
use strict; use warnings;
use Cwd;
use Getopt::Long;
use Switch;
use Text::Trim;
use Data::Dumper;

our ($cwd);
$cwd = getcwd();

sub config {
  my $class = shift;
  my $op = shift;
  my @branches = $class->_get_branches();

  if (!$op) {
    $op = Daemon::prompt("Choose an operation", undef, ['init', 'list', 'delete']);
  }

  switch ($op) {
    case 'init' {
      say "Please answer the following questions (press enter to confirm defaults):";

      my $source = Daemon::prompt('Which branch must be used as Source when creating a new branch?', 'master', [@branches]);
      my $redmine = Daemon::prompt('Do you want to enable Redmine support?', 'y') eq 'y' ? 1 : 0;
      my $pattern = $redmine ? Daemon::prompt('Please specify your branch naming convention (you can use issue properties as tokens)', 'feature/:id:-:subject:') : '';
      my $config = {
        branch => {
          source => $source,
          pattern => $pattern
        },
        redmine => $redmine
      };

      say Daemon::array2table('Memento Git configurations', [$config], {full_nested => 1});

      if (Daemon::prompt('Do you confirm these configurations?', 'y') eq 'y') {
        my $orig_config = $class->_get_config();
        if ($orig_config) {
          $class->_delete_config();
        }

        system("git config memento.branch.source " . $config->{branch}->{source});
        system("git config memento.branch.pattern " . $config->{branch}->{pattern});
        system("git config memento.redmine " . $config->{redmine});
        say "\nYour Memento Git configurations have been saved:";
        system("memento git config list");
      }
    }
    case 'list' {
      say `git config -l | grep memento`;
    }
    case 'delete' {
      $class->_delete_config();
      say "Your Memento Git configurations have been deleted.";
    }
  }
}

sub root {
  my $class = shift;
  my $goto = shift || 0;
  my $p_root = `git rev-parse --show-toplevel`;
  chomp($p_root);

  if ($goto) {
    chdir $p_root;
  }
  else {
    say $p_root;
  }
}

sub start {
  my $class = shift;
  my $config = $class->_get_config();
  my $branch;
  my @branches = $class->_get_branches();

  if (!$config) {
    die "No Memento git config has been found. Please run 'memento git config init' before start creating branches using Memento.\n"
  }
  my $source = $config->{branch}->{source};
  chomp($source);

  GetOptions(
    'source=s' => \$source
  ) or die 'Incorrect usage';

  if (!Daemon::in_array([@branches], $source)) {
    die "You have specified an invalid source branch: $source\n";
  }

  my $issue;

  if ($config->{redmine}) {
    my $id = Daemon::prompt("Enter Redmine issue id");
    $issue = $class->{redmine}->_get_issue($id);
    $branch = trim $config->{branch}->{pattern};
    $branch =~ s/:(\w+):/$issue->{$1}/g;
    $branch =~ s/:(\w+)-(\w+):/$issue->{$1}->{$2}/;
    $branch = "$branch";
  }
  else {
    $branch = Daemon::prompt("Enter the branch name");
  }

  $branch = $class->_check_branch_name($branch);

  if (Daemon::in_array([@branches], $branch)) {
    # Checkout to existing branch.
    system("git checkout $branch");
  }
  else {
    # Create a new branch from the specified source.
    system("git checkout -b $branch $source");

    # Set upstream for the new branch if a remote origin exists.
    if ($class->_get_origin() && !$class->_get_tracked_branch()) {
      system("git push --set-upstream origin $branch");
    }

    $class->_on('git_branch_creation', {branch => $branch, issue => $issue});
  }
}

# OVERRIDDEN METHODS ###########################################################

sub _dependencies {
  return ['redmine'];
}

sub _pre {
  chdir $cwd;
}

# EVENT LISTENERS ##############################################################

sub _events {
  return [
    {
      name => 'git_branch_creation',
      arguments => [
        'branch',
        'issue'
      ]
    }
  ];
}

# PRIVATE METHODS ##############################################################

sub _check_branch_name {
  my $class = shift;
  my $branch = shift or die "Missing branch to check.\n";

  $branch = lc $branch;
  $branch =~ s/[^\w\/\#\-]+/_/g; #converts anything different from the pattern.
  $branch =~ s/_+\-+_*/_/g;      #removes "_-_".
  $branch =~ s/^\w{1,2}_|_\w{1,2}_|_\w{1,2}$/_/g; #removes short words (<= 2).
  $branch =~ s/^_|_$//g;         #removes trailing and leading "_".
  return $branch;
}

sub _get_config {
  my $class = shift;
  my $config;
  my @conf = trim `memento git config list`;

  if ($#conf > 0) {
    my $source = `git config memento.branch.source`;
    my $pattern = `git config memento.branch.pattern`;
    my $redmine = `git config memento.redmine`;

    $config = {
      branch => {
        source => $source,
        pattern => $pattern
      },
      redmine => $redmine
    };
  }
}

sub _delete_config {
  my $class = shift;
  system("git config --unset memento.branch.source");
  system("git config --unset memento.branch.pattern");
  system("git config --remove-section memento.branch");
  system("git config --unset memento.redmine");
  system("git config --remove-section memento");
}

sub _get_branches {
  my $class = shift;
  my $branch_list = trim `git branch`;
  $branch_list =~ s/\* //;
  return split(' ', $branch_list);
}

sub _get_current_branch {
  my $branch = `git rev-parse --abbrev-ref HEAD`;
  chomp($branch);
  return $branch;
}

sub _get_commit_sha {
  my $sha = `git rev-parse HEAD`;
  chomp($sha);
  return $sha;
}

sub _get_origin {
  my $origin = `git config --get remote.origin.url`;
  chomp($origin);
  return $origin;
}

sub _get_tracked_branch {
  my $class = shift;
  my $branch = $class->_get_current_branch();
  my $tracked_branch = `git rev-parse --abbrev-ref $branch\@{upstream}`;
  chomp($tracked_branch);
  return $tracked_branch;
}

1;