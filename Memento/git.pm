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

sub branch {
  my $class = shift;
  my $config = $class->_get_config();
  my $branch;

  if (!$config) {
    die "No Memento git config has been found. Please run 'memento git init' before start creating branches using Memento.\n"
  }
  my $source = $config->{branch}->{source};

  GetOptions(
    'source=s' => \$source
  ) or die 'Incorrect usage';

  if ($config->{redmine}) {
    my $id = Daemon::promptUser("Enter Redmine issue id") or die "Missing Redmine issue id\n";
    my $issue = $class->{redmine}->_get_issue($id);
    $branch = trim $config->{branch}->{pattern};
    $branch =~ s/:(\w+):/$issue->{$1}/g;
    $branch = "$branch";
  }
  else {
    $branch = Daemon::promptUser("Enter the branch name") or die "Missing branch name, procedure aborted.\n";
  }

  $branch = $class->_check_branch_name($branch);
  system("git checkout -b $branch $source");
}

sub config {
  my $class = shift;
  my $op = shift || 'list';
  #my @branches = `git branch`;

  switch ($op) {
    case 'init' {
      say "Please answer the following questions (press enter to confirm defaults):";
      my $source = Daemon::promptUser('Which branch must be used as Source when creating a new branch?', 'master');
      my $redmine = Daemon::promptUser('Do you want to enable Redmine support?', 'y') eq 'y' ? 1 : 0;
      my $pattern = Daemon::promptUser('Please specify your branch naming convention (if you answered yes in the previous question you can use issue properties as tokens):', '#:id:_:subject:');

      my $config = {
        branch => {
          source => $source,
          pattern => $pattern
        },
        redmine => $redmine
      };

      say Daemon::array2table('Memento Git configurations', [$config], {full_nested => 1});

      if (Daemon::promptUser('Do you confirm these configurations?', 'y') eq 'y') {
        system("git config memento.branch.source " . $config->{branch}->{source});
        system("git config memento.branch.pattern " . $config->{branch}->{pattern});
        system("git config memento.redmine " . $config->{redmine});
        say "\nYour Memento Git configurations have been saved:";
        system("memento git config");
      }
    }
    case 'list' {
      say `git config -l | grep memento`;
    }
    case 'delete' {
      system("git config --unset memento.branch.source");
      system("git config --unset memento.branch.pattern");
      system("git config --unset memento.redmine");
      system("memento git config");
    }
  }
}

sub ignore {
  my $class = shift;
  my $ignore = shift;
  $class->root(1);
  Daemon::write(".gitignore", $ignore, 1, '>>');
  say "$ignore added to .gitignore";
}

sub remove {
  my $class = shift;
  my $file = shift;
  if (!-e $file) {
    die("Trying to remove not existing file: $file");
  }
  $class->root(1);
  `git reset $file`;
  $class->status();
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

sub status {
  say `git status -s`;
}

# OVERRIDDEN METHODS ###########################################################

sub _dependencies {
  return ['redmine'];
}

sub _pre {
  my $class = shift;
  $class->SUPER::_pre();
  chdir $cwd;
}

# PRIVATE METHODS ##############################################################

sub _check_branch_name {
  my $class = shift;
  my $branch = shift or die "Missing branch to check.\n";

  $branch = lc $branch;
  $branch =~ s/^feature\///;
  $branch =~ s/\W+/_/g;
  $branch =~ s/^\w{1,2}_|_\w{1,2}_|_\w{1,2}$/_/g;
  $branch =~ s/^_|_$//g;
  $branch = "feature/$branch";
  return $branch;
}

sub _get_config {
  my $class = shift;
  my $config;
  my @conf = trim `memento git config`;

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

sub _token_replace {
   my ($pat, $args) = @_;
   die Dumper($pat, $args);
   my $t = String::Interpolate->new($args);
   $t->($pat);
   return "$t";
}

1;