#!/usr/bin/perl
package Memento;
use strict; use warnings;
use feature 'say';

my $file = `which memento`;
$_ = `ls -l $file`;

our $root = undef;
if (/ (\/[\w\/\-]+?memento\.pl)$/) {
  $root = $1;
  $root =~ s/\/memento.pl$//;
}

require "$root/Daemon.pm";

if ($#ARGV > -1) {
  my $type = shift;
  my $command = shift || "help";
  if (my $memento = Memento->instantiate($type)) {
    $memento->$command(@ARGV);
  }
}
else {
  say Daemon::read("$root/misc/splash");
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
