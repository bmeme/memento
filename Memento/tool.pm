#!/usr/bin/env perl
package Memento::Tool;

use feature 'say';
use Data::Dumper;

our ($root, @args, $instances);
$root = Memento::Tool->root();

sub commands {
  my @list;
  my $i = 0;
  my $commands_dir = "$root/Memento/Tool";
  my @commands;

  opendir(DIR, $commands_dir) || die "Can't open directory $commands_dir: $!";
  @list = grep /\.pm$/, readdir(DIR);
  closedir DIR;

  for my $command (sort @list) {
    $command =~ s/\.pm$//;
    push (@commands, $command);
  }

  return @commands;
}

sub instantiate {
  my $class = shift;
  my $type = shift;
  my $command = shift || "";
  my $location = "Memento/Tool/$type.pm";
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
