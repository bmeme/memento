#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Memento/Command.pm";
our ($root);

package Memento::Tool::features;

use feature 'say';
our @ISA = qw(Memento::Command);
use strict; use warnings;
use JSON::PP;
use Data::Dumper;
use Getopt::Long;

sub export {
  my $class = shift;
  my $command = shift;
  my @commands = $class->_get_commands($command);
  my $features = {};

  foreach my $command (@commands) {
    if ($command ne 'all') {
      my $tool = Memento::Tool->instantiate($command);
      $features->{$command} = $tool->_get_config();
    }
  }

  say JSON::PP->new->utf8->pretty->encode($features);
}

sub import {
  my $class = shift;
  my $command = shift;
  my @commands = $class->_get_commands($command);
  my $import = {};
  my $file;

  GetOptions(
    'file=s' => \$file
  ) or die 'Incorrect usage';

  if (!$file) {
    $file = Daemon::prompt("Enter import file path");
  }

  my $features = Daemon::json_decode_file($file);

  foreach my $command (@commands) {
    if ($command ne 'all') {
      print "[-] $command";
      my $tool = Memento::Tool->instantiate($command);
      $tool->_save_config($features->{$command}) or print "\r[x] $command\n";
      print "\r[√] $command\n";
    }
  }
}

sub _get_commands {
  my $class = shift;
  my $command = shift;
  my @commands = ('all');

  foreach my $cmd (Memento::Tool->commands()) {
    if ($cmd ne 'features') {
      push(@commands, $cmd);
    }
  }

  if (!$command) {
    $command = Daemon::prompt("Choose a feature", undef, [@commands]);
  }

  if ($command ne 'all') {
    @commands = ($command);
  }

  return @commands;
}

1;