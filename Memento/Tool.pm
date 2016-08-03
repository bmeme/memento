#!/usr/bin/env perl
package Memento::Tool;

use feature 'say';
use Data::Dumper;

our ($root, @args, $instances);
$root = Memento::Tool->root();

sub commands {
  my @list;
  my $i = 0;
  my @commands_dir = ("Memento/Tool", "Memento/Tool/custom");
  my $commands = {};

  foreach my $commands_dir (@commands_dir) {
    opendir(DIR, "$root/$commands_dir") || die "Can't open directory $commands_dir: $!";
    @list = grep /\.pm$/, readdir(DIR);
    closedir DIR;

    for my $command (@list) {
      $command =~ s/\.pm$//;
      $commands->{$command} = $commands_dir;
    }
  }

  return $commands;
}

sub instantiate {
  my $class = shift;
  my $type = shift;
  my $command = shift || "";
  my $commands = $class->commands();
  my $location = "$commands->{$type}/$type.pm";
  $class = "Memento::Tool::$type";
  my $instance;

  if (defined $instances->{$type}) {
    $instance = $instances->{$type};
  }
  else {
    if (-f "$root/$location") {
      require "$root/$location";
      $instance = $class->new(@_, $type, $command);
      $instances->{$type} = $instance;
    }
  }

  return $instance;
}

sub root {
  if (!$root) {
    my $memento_link = `which memento`;
    chomp($memento_link);

    if (length($memento_link)) {
      $root = readlink($memento_link);
      $root =~ s/\/memento\.pl$//;
    }
    else {
      die "Memento was not installed correctly, please try again.\n";
    }
  }

  return $root;
}

1;
