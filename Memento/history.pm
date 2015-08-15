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

sub list {
  my $class = shift;
  print $class->_get_list();
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
    Daemon::write($class->{storage}, 'memento', 1, '>');
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