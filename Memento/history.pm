#!/Applications/MAMP/Library/bin/perl
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
  my $i = shift;
  my @list = $class->_get_list();

  if (defined $list[$i]) {
    system($list[$i]);
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