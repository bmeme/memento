#!/usr/bin/env perl
require "$root/Daemon.pm";

package Memento::Command;

use strict; use warnings;
use feature 'say';
use Class::MOP;
use base qw(Class::Observable);
use JSON::PP;
use Text::Trim;
use Data::Dumper;

our ($root);
$root = Memento::Tool->root();

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
      $self->{$dependency} = Memento::Tool->instantiate($dependency);
    }
  }

  my $instance = bless $self, $class;

  # Add observers in order to allow interactions with other tools.
  my $commands = Memento::Tool->commands();
  for my $tool (keys %{$commands}) {
    my $location = "$root/$commands->{$tool}/$tool.pm";
    require $location;
    $instance->add_observer("Memento::Tool::$tool");
  }

  return $instance;
}

sub help {
  my $class = shift;
  my $class_name = undef;
  if ($class =~ /(^\w+::\w+::\w+)=/i) {
    $class_name = $1;
    my $meta = Class::MOP::Class->initialize($class_name);
    my @methods = sort $meta->get_method_list;
    my @commands = ();

    for my $method (@methods) {
      if ($method =~ /^[a-z]/i && ($method ne 'update')) {
        push (@commands, $method);
      }
    }

    my $command = Daemon::prompt("Choose a command", undef, [@commands]);
    system("memento $class->{type} $command");
  }
}

sub update {
  my $class = shift;
  my $tool = $class;
  $tool =~ s/^Memento\:\:Tool\:\://;
  $class = Memento::Tool->instantiate($tool);

  my ($item, $event) = @_;
  if ($class->can($event)) {
    $class->$event($item, $event, $_[2][0]);
  }
}

sub _events {
  return [];
}

sub _conditions {
  return [];
}

sub _actions {
  return [];
}

sub _on {
  my $class = shift;
  my $event = shift;
  my @params = @_;
  my $events = ['pre_execution', 'post_execution'];

  foreach my $class_event (@{$class->_events()}) {
    push (@{$events}, $class_event->{name});
  }

  if (Daemon::in_array($events, $event)) {
    $class->notify_observers("_on_$event", \@params);
  }
}

sub _pre {
  my $class = shift;
  Daemon::printLabel("[Memento] » " . $class->{type});
}

sub _done {
  # nothing to do by default.
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

sub _get_storage {
  my $class = shift;
  my $storage;

  if (-f $class->{storage}) {
    $storage = Daemon::json_decode_file($class->{storage});
  }
  else {
    $storage = {};
    $class->_save_storage($storage);
  }

  return $storage;
}

sub _save_storage {
  my $class = shift;
  my $storage = shift;
  Daemon::write($class->{storage}, JSON::PP->new->utf8->pretty->encode($storage), '1', '>');
}

sub _log_history {
  return 1;
}

sub _dependencies {
  return [];
}

1;