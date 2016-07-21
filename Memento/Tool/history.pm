#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Memento/Command.pm";

package Memento::Tool::history;

use feature 'say';
our @ISA = qw(Memento::Command);
use strict; use warnings;
use Getopt::Long;
use Switch;
use Text::Trim;
use Data::Dumper;

sub bookmark {
  my $class = shift;
  my $mode = shift;
  my $config = $class->_get_config();
  my $id;
  my $name;
  my $command = '';
  my @list = $class->_get_list();
  my $modes = ['history', 'last', 'manual'];

  if (!$mode || !Daemon::in_array($modes, $mode)) {
    $mode = Daemon::prompt("Choose a bookmark modality", 'history', $modes);
  }

  switch ($mode) {
    case 'history' {
      say $class->list();
      do {
        $id = Daemon::prompt("Insert the history ID of the command to bookmark");
        $command = $list[$id];
      }
      while (!defined $list[$id]);
    }
    case 'last' {
      $command = $class->_get_last();
    }
    case 'manual' {
      $command = Daemon::prompt("Write the command to bookmark");
    }
  }
  chomp($command);

  do {
    $name = Daemon::prompt("Provide a machine_name to bookmark this command");
  }
  while ($name !~ /^[\w!\-]+$/);

  my $bookmark = {
    name => $name,
    command => $command
  };

  push (@{$config->{bookmarks}}, $bookmark);
  $class->_save_config($config);
  $class->bookmarks();
}

sub bookmarks {
  my $class = shift;
  my $config = $class->_get_config();
  say Daemon::array2table("Bookmarks", $config->{bookmarks});
}

sub clear {
  my $class = shift;
  Daemon::write($class->{storage}, 'memento', 1, '>');
}

sub exec {
  my $class = shift;
  my $id = shift || Daemon::prompt('Insert the history ID of the command to be executed');
  my @list = $class->_get_list();

  if (defined $list[$id]) {
    system($list[$id]);
  }
  else {
    die "Command not found in history for id $id.\n";
  }
}

sub last {
  my $class = shift;
  my $last = $class->_get_last();
  my $execute = 0;
  GetOptions(
    'execute!' => \$execute
  ) or die 'Incorrect usage';

  if ($execute && !($last =~ /^$class->{base_command}/)) {
    system($last);
  }
  else {
    say $last;
  }
}

sub list {
  my $class = shift;
  my @list = $class->_get_list();
  for (my $i = 0; $i <= $#list; $i++) {
    my $item = "[$i] $list[$i]";
    if ($i == ($#list + 1)) {
      say $item;
    }
    else {
      print $item;
    }
  }
}

sub unbookmark {
  my $class = shift;
  my $name = shift;

  if (!$name) {
    $name = Daemon::prompt("Enter the name of the bookmark to delete");
  }

  my $config = $class->_get_config();
  my $deleted = 0;
  my $i = 0;
  for my $bookmark (@{$config->{bookmarks}}) {
    if ($bookmark->{name} eq $name) {
      delete $config->{bookmarks}[$i];
      $deleted = 1;
    }
    $i++;
  }

  if ($deleted) {
    $class->_save_config($config);
    say "Bookmark '$name' deleted.";
    $class->bookmarks();
  }
  else {
    say "Bookmark '$name' not found.";
  }
}

# OVERRIDDEN METHODS ###########################################################

sub _def_config {
  return {
    bookmarks => []
  };
}

# EVENT LISTENERS ##############################################################

sub _on_pre_execution {
  my $class = shift;
  my $subject = shift;
  my $action = shift;

  if ($subject->_log_history()) {
    my $arg = shift || '';
    my $full_command = trim "$subject->{base_command} $arg @_";
    my $history = Memento::Tool->instantiate('history');

    if ($full_command ne $history->_get_last()) {
      Daemon::write($history->{storage}, $full_command, 1, '>>');
    }
  }
}

# PRIVATE METHODS ##############################################################

sub _get_list {
  my $class = shift;
  if (!-f $class->{storage}) {
    $class->clear();
  }
  return `cat $class->{storage}`;
}

sub _get_last {
  my $class = shift;
  my @content = $class->_get_list();
  return ($#content != -1) ? trim $content[$#content] : '';
}

sub _log_history {
  return 0;
}

1;