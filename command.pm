#!/Applications/MAMP/Library/bin/perl
require "$root/Daemon.pm";
require "$root/Memento/history.pm";

package Command;

use strict; use warnings;
use feature 'say';
use Class::MOP;
use Text::Trim;
use Data::Dumper;

sub new {
  my $class = shift;
  my $type = shift;
  my $command = shift;
  my $self = {
    type => $type,
    command => $command,
    base_command => "memento $type $command",
    storage => Daemon::storage() . "/$type"
  };
  return bless $self, $class;
}

sub help {
  my $class = shift;
  my $class_name = undef;
  if ($class =~ /(^\w+::\w+)=/i) {
    $class_name = $1;
    my $meta = Class::MOP::Class->initialize($class_name);
    my @methods = sort $meta->get_method_list;
    for my $method (@methods) {
      if ($method =~ /^[a-z]/i) {
        say $method;
      }
    }
  }
}

sub _pre {
  my $class = shift;

  if ($class->_log_history()) {
    my $arg = shift || '';
    my $clean_command = trim "$class->{base_command} $arg";
    my $full_command = trim "$class->{base_command} $arg @_";
    my $history = Memento->instantiate('history', 'list');

    if ($full_command ne $history->_get_last()) {
      Daemon::write($history->{storage}, $full_command, 1, '>>');
    }
  }
}

sub _done {
  # nothing to do by default;
}

sub _log_history {
  return 1;
}

1;