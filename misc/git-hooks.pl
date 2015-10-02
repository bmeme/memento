#!/usr/bin/env perl

use feature 'say';
use Data::Dumper;
use Git::Hooks;
use Cwd;

our ($root);
$root = `memento schema root`;
chomp $root;

require "$root/Daemon.pm";
require "$root/Memento/Tool.pm";

my $git = Memento::Tool->instantiate('git');
my $config = $git->_get_config();
my $hook = "$0";
$hook =~ s/^\.git\/hooks\///;
$hook =~ s/\-/_/;

COMMIT_MSG {
  if (!$config->{hooks}->{$hook}) {
    return 0;
  }
  Daemon::printLabel("memento - $hook");
  my $git_hooks = shift;
  my $commit_message_file = shift;

  $git->root(1);
  my @commit_message = Daemon::read($git_hooks->{opts}->{WorkingCopy} . $commit_message_file);
  my $message = "@commit_message";
  chomp($message);

  my $params = {
    success => 1,
    errors => [],
    message => $message,
    branch => $git->_get_current_branch()
  };
  $git->_on("git_$hook", \$params);

  if ($params->{success} != 1) {
    foreach my $error (@{$params->{errors}}) {
      $git_hooks->error("memento - $hook", $error);
    }
    return 0;
  }

  return 1;
};

PRE_COMMIT {
  if (!$config->{hooks}->{$hook}) {
    return 0;
  }
  Daemon::printLabel("memento - $hook");
  my $git_hooks = shift;
  my $head = `git rev-parse --verify HEAD`;
  my $against = $head ? 'HEAD' : '4b825dc642cb6eb9a060e54bf8d69288fbee4904';
  my @commit_files = `git diff-index --cached --name-only $against`;
  chomp(@commit_files);

  my $params = {
    success => 1,
    errors => [],
    branch => $git->_get_current_branch(),
    commit_files => [@commit_files]
  };

  $git->_on("git_$hook", \$params);

  if ($params->{success} != 1) {
    foreach my $error (@{$params->{errors}}) {
      $git_hooks->error("memento - $hook", $error);
    }
    return 0;
  }

  return 1;
};

POST_COMMIT {
  if (!$config->{hooks}->{$hook}) {
    return 0;
  }
  Daemon::printLabel("memento - $hook");
  my $git_hooks = shift;
  my $params = {
    success => 1,
    errors => [],
    branch => $git->_get_current_branch()
  };
  $git->_on("git_$hook", \$params);

  if ($params->{success} != 1) {
    foreach my $error (@{$params->{errors}}) {
      $git_hooks->error("memento - $hook", $error);
    }
    return 0;
  }

  return 1;
};

run_hook($0, @ARGV);
