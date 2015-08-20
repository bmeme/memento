#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Memento/history.pm";

package Command;

use strict; use warnings;
use feature 'say';
use Class::MOP;
use JSON::PP;
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
    storage => Daemon::storage() . "/$type",
    config => Daemon::storage() . "/" . $type . "_cfg",
  };

  if ($class->_dependencies()) {
    for my $dependency (@{$class->_dependencies()}) {
      $self->{$dependency} = Memento->instantiate($dependency, '');
    }
  }

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

sub _def_config {
  my $class = shift;
  return {};
}

sub _get_config {
  my $class = shift;
  my $config;

  if (-f $class->{config}) {
    $config = Daemon::json_decode_file($class->{config});
  }
  else {
    $config = $class->_def_config();
    $class->_save_config($config);
  }

  return $config;
}

sub _save_config {
  my $class = shift;
  my $config = shift;
  Daemon::write($class->{config}, JSON::PP->new->utf8->pretty->encode($config), '1', '>');
}

sub _log_history {
  return 1;
}

sub _dependencies {
  return [];
}

1;