#!/usr/bin/env perl
package Memento;
use strict; use warnings;
use feature 'say';
use Data::Dumper;
use Getopt::Std;
$Getopt::Std::STANDARD_HELP_VERSION = 1;

our ($root, @args);

my $file = `which memento`;
$_ = `ls -l $file`;

if (/ (\/[\w\/\-]+?memento\.pl)$/) {
  $root = $1;
  $root =~ s/\/memento.pl$//;
}

require "$root/Daemon.pm";
getopts('vh');

@args = @ARGV;
if ($#ARGV > -1) {
  my $type = shift;
  my $command = shift || "help";
  if (my $memento = Memento->instantiate($type, $command)) {
    $memento->_pre(@ARGV);
    $memento->$command(@ARGV);
    $memento->_done(@ARGV);
  }
  else {
    shift @args;
    my $history = Memento->instantiate('history', 'bookmarks');
    my $bookmarks = $history->_get_config()->{bookmarks};
    for my $bookmark (@{$bookmarks}) {
      if ($bookmark->{name} eq $type) {
        system($bookmark->{command} . " @args");
      }
    }
  }
}
else {
  my @list;
  my $i = 0;
  my $commands_dir = "$root/Memento";
  my @commands;

  opendir(DIR, $commands_dir) || die "Can't open directory $commands_dir: $!";
  @list = grep /\.pm$/, readdir(DIR);
  closedir DIR;

  for my $command (sort @list) {
    $command =~ s/\.pm$//;
    push (@commands, $command);
  }
  my $command = Daemon::prompt("Choose a tool", undef, [@commands]);
  system("memento $command");
}

sub instantiate {
  my $class = shift;
  my $type = shift;
  my $command = shift;
  my $location = "Memento/$type.pm";
  $class = "Memento::$type";

  if (-f "$root/$location") {
    require "$root/$location";
    return $class->new(@_, $type, $command);
  }
}

sub splash {
  return Daemon::read("$root/splash");
}

sub main::VERSION_MESSAGE {
  say &splash();
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Memento

=head1 VERSION

version 0.3.0

=head1 SYNOPSIS

memento [-OPTIONS [-MORE_OPTIONS]] [--] [PROGRAM_ARG1 ...]

The following single-character options are accepted:
  Boolean (without arguments): --version --help

=head1 DESCRIPTION

B<memento> is a step by step command line tool.
Basically it provides three types of commands:

  - git
  - history
  - redmine

Memento, for each command, provides by default a fallback helper if a
required argument is missing. For example you can get your last executed
command via direct input:

  $ memento history last
  memento git status

or via progressive input:

  $ memento
  Enter the tool name to be used:
  - git
  - history
  - redmine
  » history

  Choose a command:
  - bookmark
  - bookmarks
  - clear
  - exec
  - last
  - list
  - unbookmark
  » last

  memento git status

=head1 HISTORY

Every command executed is logged into the memento history and can be bookmarked
as a shortcut.

I<memento history> provides the following operations:

=over 2

=item I<bookmark>

Bookmarks a command creating a new shortcut.

=item I<bookmarks>

Lists all available bookmarks.

=item I<clear>

Clear the command history.

=item I<exec>

Executes a command previously logged into the command history.

=item I<last [--execute]>

Get last executed command. Use B<--execute> option to execute it.

=item I<list>

Lists all commands logged into the command history.

=item I<unbookmark>

Deletes a bookmarked command.

=back



=head1 REDMINE

You can easily integrate Memento with multiple instances of Redmine, with the
I<memento redmine config add> command, and switch from one to another simply by
using the I<memento redmine config switch [redmine_api_id]> command.

I<memento redmine> provides the following operations:

=over 2

=item I<config>

Manages Redmine API configurations providing the following options:

=over 2

=item I<add>

Adds a new configurations set for a Redmine instance.

=item I<delete [redmine_api_id]>

Deletes a configurations set for a Redmine instance.

=item I<list>

Lists all Redmine configurations.

=item I<switch [redmine_api_id]>

Sets a Redmine instance as the default one. All queries will be executed to the
default one.

=back

=item I<issue [redmine_issue_id [--open]]>

Shows the details of an issue. If the B<--open> boolean option has been provided,
the issue sill not be rendered, but opened into your default web browser.

=item I<projects>

Renders a table containing info about all available Redmine projects.

=item I<queries>

Renders a table containing info about all available Redmine custom queries.

=item I<query [redmine_query_id]>

Renders a table containing info about all available Redmine issue extracted from
the custom query.

=back



=head1 GIT

I<memento git> is a configurable tool with the main purpose to help developers
creating branch, following git-flow-like (but divergent) flows. This is not a
wrapper around git core features, but just something like an extension.

I<memento git> provides the following operations:

=over 2

=item I<branch [--source]>

Creates a new branch starting from the configured source branch. Use B<--source>
option to override the default one. If during the configuration operation, the
Redmine support was enabled, you will be asked to insert a Redmine Issue Id. It
will be used to build the new branch, following the configured branch pattern.

=item I<config>

Manages Memento Git configurations providing the following options:

=over 2

=item I<init>

Initialize your git repository storing configurations that will be used for
branches creation.

=item I<list>

Lists all Memento Git configurations.

=item I<delete>

Delete all Memento Git configurations affecting your current repository.

=back


=head1 USAGE

memento [-OPTIONS [-MORE_OPTIONS]] [--] [PROGRAM_ARG1 ...]

The following single-character options are accepted:
  Boolean (without arguments): -v -h

Options may be merged together.  -- stops processing of options.

=head1 BUGS

None known as of release, but...

=head1 AUTHOR

Adriano Cori <adriano.cori@bmeme.com>

=head1 COPYRIGHT

Copyright (c) 2015 Adriano Cori. All rights reserved.
This program is free software; you can redistribute
it and/or modify it under the terms of the ISC license.

(This program had been licensed under the same terms as Perl itself up to
version 1.118 released on 2011, and was relicensed by permission of its
originator).

The full text of the license can be found in the
LICENSE file included with this module.

=head1 AUTHOR

Bonsaimeme S.r.l. <http://www.bmeme.com>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2105 by Adriano Cori.

This is free software, licensed under:

  The MIT (X11) License

=cut
