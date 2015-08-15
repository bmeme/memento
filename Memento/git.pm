#!/Applications/MAMP/Library/bin/perl
require "$root/Daemon.pm";
require "$root/Command.pm";

package Memento::git;

use feature 'say';
our @ISA = qw(Command);
use strict; use warnings;

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
  my $goto = shift;
  my $p_root = `git rev-parse --show-toplevel`;
  chop($p_root);

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

1;