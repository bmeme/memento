#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Memento/history.pm";

package Command;

use strict; use warnings;
use feature 'say';
use Class::MOP;
use base qw( Class::Observable );
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
    my @commands = ();
    for my $method (@methods) {
      if ($method =~ /^[a-z]/i) {
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
  $tool =~ s/^Memento\:\://;
  $class = Memento->instantiate($tool, '');

  my ($item, $action) = @_;
  my $event = "_on_$action";

  if ($class->can($event)) {
    $class->$event(@_);
  }
}

sub _pre {
  # nothing to do by default.
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

sub _log_history {
  return 1;
}

sub _dependencies {
  return [];
}

1;