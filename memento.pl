#!/usr/bin/env perl
package Memento;
use strict; use warnings;
use feature 'say';
use Data::Dumper;
use Getopt::Std;
$Getopt::Std::STANDARD_HELP_VERSION = 1;

our ($root, @args);

my $file = `which memento`;
$_ = `ls -l $file`;

if (/ (\/[\w\/\-]+?memento\.pl)$/) {
  $root = $1;
  $root =~ s/\/memento.pl$//;
}

require "$root/Daemon.pm";
getopts('vh');

@args = @ARGV;
if ($#ARGV > -1) {
  my $type = shift;
  my $command = shift || "help";
  if (my $memento = Memento->instantiate($type, $command)) {
    $memento->_pre(@ARGV);
    $memento->$command(@ARGV);
    $memento->_done(@ARGV);
  }
  else {
    shift @args;
    my $history = Memento->instantiate('history', 'bookmarks');
    my $bookmarks = $history->_get_config()->{bookmarks};
    for my $bookmark (@{$bookmarks}) {
      if ($bookmark->{name} eq $type) {
        system($bookmark->{command} . " @args");
      }
    }
  }
}
else {
  my @list;
  my $i = 0;
  my $commands_dir = "$root/Memento";

  opendir(DIR, $commands_dir) || die "Can't open directory $commands_dir: $!";
  @list = grep /\.pm$/, readdir(DIR);
  closedir DIR;

  for my $command (sort @list) {
    $command =~ s/\.pm$//;
    if ($i == ($#list + 1)) {
      print "- $command";
    }
    else {
      say "- $command";
    }
  }
}

sub instantiate {
  my $class = shift;
  my $type = shift;
  my $command = shift;
  my $location = "Memento/$type.pm";
  $class = "Memento::$type";

  if (-f "$root/$location") {
    require "$root/$location";
    return $class->new(@_, $type, $command);
  }
}

sub splash {
  return Daemon::read("$root/splash");
}

sub main::VERSION_MESSAGE {
  say &splash();
}

1;
