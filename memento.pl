#!/usr/bin/perl
package Memento;
use strict; use warnings;
use Data::Dumper;

my $file = `which memento`;
$_ = `ls -l $file`;

our $root = undef;
if (/ (\/[\w\/\-]+?memento\.pl)$/) {
  $root = $1;
  $root =~ s/\/memento.pl$//;
}

if ($#ARGV > -1) {
  my $type = shift;
  my $command = shift || "help";
  if (my $memento = Memento->instantiate($type)) {
    $memento->$command(@ARGV);
  }
}
else {
  print "._____.___ ._______._____.___ ._______.______  _____._._______\n"
       .":         |: .____/:         |: .____/:      \\ \\__ _:|: .___  \\\n"
       ."|   \\  /  || : _/\\ |   \\  /  || : _/\\ |       |  |  :|| :   |  |\n"
       ."|   |\\/   ||   /  \\|   |\\/   ||   /  \\|   |   |  |   ||     :  |\n"
       ."|___| |   ||_.: __/|___| |   ||_.: __/|___|   |  |   | \\_. ___/\n"
       ."      |___|   :/         |___|   :/       |___|  |___|   :/\n"
       ."                                                         :\n";
  print "Version: 0.1-alpha - 2015 - © Adriano Cori.\n";
}

sub instantiate {
  my $class = shift;
  my $type = shift;
  my $location = "Memento/$type.pm";
  $class = "Memento::$type";

  if (-f "$root/$location") {
    require "$root/$location";
    return $class->new(@_);
  }
}

1;
