#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Command.pm";

package Memento::history;

use feature 'say';
our @ISA = qw(Command);
use strict; use warnings;
use Getopt::Long;
use Text::Trim;
use Data::Dumper;

sub clear {
  my $class = shift;
  Daemon::write($class->{storage}, 'memento', 1, '>');
}

sub exec {
  my $class = shift;
  my $id = shift or die "Insert the history ID of the command to be executed.\n";
  my @list = $class->_get_list();

  if (defined $list[$id]) {
    system($list[$id]);
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

sub bookmark {
  my $class = shift;
  my $config = $class->_get_config();
  my $id;
  my $name;
  my $command;
  my @list = $class->_get_list();

  if (Daemon::promptUser("Do you want to bookmark your last command?", "y") eq 'y') {
    $command = $class->_get_last();
  }
  else {
    say $class->list();
    do {
      $id = Daemon::promptUser("Insert the history ID of the command to be saved as a preset");
      $command = $list[$id];
    }
    while (!defined $list[$id]);
  }
  chomp($command);

  do {
    $name = Daemon::promptUser("Provide a machine_name to bookmark this command");
  }
  while ($name !~ /^\w+$/);

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
  Daemon::array2table("Bookmarks", $config->{bookmarks});
}

sub unbookmark {
  my $class = shift;
  my $name = shift or die "Enter the name of the bookmark to delete\n";
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
  return trim $content[$#content];
}

sub _log_history {
  return 0;
}

1;