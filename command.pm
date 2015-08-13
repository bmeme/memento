#!/usr/bin/perl
package Command;

use strict; use warnings;
use feature 'say';
use Class::MOP;

sub new {
  my $class = shift;
  my $self = {};
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

1;