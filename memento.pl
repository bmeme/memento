#!/usr/bin/env perl
package Memento;
use strict; use warnings;
use feature 'say';
use Getopt::Std;
$Getopt::Std::STANDARD_HELP_VERSION = 1;

our ($root, @args);

my $memento_link = `which memento`;
chomp($memento_link);

if (length($memento_link)) {
  $root = readlink($memento_link);
  $root =~ s/\/memento\.pl$//;
}
else {
  die "Memento was not installed correctly, please try again.\n";
}

require "$root/Daemon.pm";
require "$root/Memento/Tool.pm";
getopts('vh');

my $commands = Memento::Tool->commands();
@args = @ARGV;

if ($#ARGV > -1) {
  my $type = shift;
  my $command = shift || "help";
  my $git = Memento::Tool->instantiate('git');

  # change active directory to the project root so that memento commands can be
  # executed from anywhere within the project.
  $git->root(1);

  if (my $tool = Memento::Tool->instantiate($type, $command)) {
    if (!$tool->can($command) || $command =~ /^_/) {
      say "Trying to use an invalid command.";
      $command = "help";
    }

    # allow interaction with other tools before command execution.
    $tool->_on('pre_execution', @ARGV);

    # let the tool prepares itself before the command execution.
    $tool->_pre(@ARGV);
    # execute the tool command.
    $tool->$command(@ARGV);
    # let the tool executes its closing operations after command execution.
    $tool->_done(@ARGV);

    # allow interaction with other tools after command execution.
    $tool->_on('post_execution', @ARGV);
  }
  else {
    shift @args;
    my $history = Memento::Tool->instantiate('history');
    my $bookmarks = $history->_get_config()->{bookmarks};
    my $found = 0;
    for my $bookmark (@{$bookmarks}) {
      if ($bookmark->{name} eq $type) {
        $found = 1;
        system($bookmark->{command} . " @args");
      }
    }

    if (!$found) {
      say "Trying to use an invalid tool.\n";
      system("memento");
    }
  }
}
else {
  my $command = Daemon::prompt("Choose a tool", undef, [sort keys %{$commands}]);
  system("memento $command");
}

sub main::VERSION_MESSAGE {
  say &splash();
}

sub splash {
  return Daemon::read("$root/splash");
}

sub root {
  return $root;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

memento

=head1 VERSION

version 1.12.1

=head1 SYNOPSIS

memento [TOOL [COMMAND [COMMAND_ARG1 ...]]] [--OPTIONS [--MORE_OPTIONS]]

=head1 DESCRIPTION

B<memento> is a modular step by step command line tool.
By default it provides the following commands:

  - activity
  - bitbucket
  - features
  - git
  - gitlab
  - history
  - jira
  - paymo
  - redmine
  - schema
  - taiga
  - tempo
  - workflow

Memento, for each command, provides by default a fallback helper if a
required argument is missing. For example you can get your last executed
command via direct input:

  $ memento history last
  memento git status

or via progressive input:

  $ memento
  Enter the tool name to be used:
  - activity
  - bitbucket
  - features
  - git
  - gitlab
  - history
  - jira
  - paymo
  - redmine
  - schema
  - taiga
  - tempo
  - workflow
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

If you want to extend Memento with your own tools, put them into B<Memento/Tool/custom>
directory. The best tools will be added into Memento core tools, so feel free to send us your tool!

=head1 INSTALLATION

In order to be able to manage third party perl modules Memento requires B<cpan>
(http://www.cpan.org/).

Open a terminal and execute the B<install.pl> file located into memento dir:

C<< ./install.pl >>

=over 2

=item I<On Ubuntu>

Before install Memento, be sure to have I<perl-doc> and I<libwww-curl-perl>:

C<< sudo apt-get install perl-doc >>

C<< sudo apt-get install libwww-curl-perl >>

C<< sudo ./install.pl >>

=back


=head1 AFTER INSTALL

After install process has ended please add the lines shown by the install script
to your .bashrc or .zshrc file:

memento schema check

<memento-install-dir>/misc/completion.sh


=head1 ACTIVITY

I<memento activity> is a configurable tool which will help you keeping track of
your activities progression and the time spent on it. If you want you can
configure it so that you can use it in conjunction with an issue tracker and a
time tracker.

I<memento activity> provides the following operations:

=over 2

=item I<config>

Manages Memento Activity configurations providing the following operations:

=over 2

=item I<init [--project]>

Initialize your Activity configurations that will be used for defining which
issue tracker and / or time tracker will be used.

=item I<list>

Lists all Memento Activity configurations.

=item I<delete>

Delete all Memento Activity configurations.

=back

=item I<start [issue-id] [--issue-tracker] [--time-tracker] [--manual]>

Starts a new activity. Use B<--manual> option if you don't need to use an Issue
Tracker. If during the configuration operation, the Issue Tracker support was
enabled, you will be asked to insert an Issue Id, or you
can provide it inline I<memento activity start [issue-id]>. It will be
used to extract the activity name from the issue and to change the its status.
Via the I<workflow> tool, it's possible to create a rule for updating issue
status and done ratio on activity start, automatically assigning it to current
user, and optionally add a comment.

=item I<stop>

Use this command when you've to stop working on your activity.
Via the I<workflow> tool, it's possible to create a rule for updating issue
status and done ratio on activity stop and optionally add a comment.

=item I<resume>

If you have previously stopped your activity, you can always resume it by using
this command.

=item I<current [--open]>

You can view what's your current activity by using this command.
If you wanna open it in your browser, then use the --open option.

=back



=head1 BITBUCKET

Due to its API limitations, Bitbucket issue tracker can only be used for branch
naming generation. No change issue status or assignee neither comments creation
operations can be done.

You can easily integrate Memento with multiple instances of Bitbucket, with the
I<memento bitbucket config add> command, and switch from one to another simply
by using the I<memento bitbucket config switch [bitbucket_api_id]> command.

I<memento bitbucket> provides the following operations:

=over 2

=item I<config>

Manages Bitbucket API configurations providing the following options:

=over 2

=item I<add>

Adds a new configurations set for a Bitbucket instance.

=item I<delete [bitbucket_api_id]>

Deletes a configurations set for a Bitbucket instance.

=item I<list>

Lists all Bitbucket configurations.

=item I<switch [bitbucket_api_id]>

Sets a Bitbucket instance as the default one. All queries will be executed to the
default one. Otherwise, you can change on the fly the active Bitbucket instance by
using the B<--api-id> option, for each memento bitbucket command.

=back

=item I<issue [bitbucket_issue_id [--open]]>

Shows the details of an issue. If the B<--open> boolean option has been provided,
the issue will not be rendered, but opened into your default web browser.

=item I<projects>

Renders a table containing info about all available Bitbucket projects.

=item I<user>

Renders a table containing info about current user referring to the active api.

=back



=head1 FEATURES

I<memento features> allows you to export and import all your tools configurations.

It provides the following operations:

=over 2

=item I<export>

Export configurations of your tools (features). You can choose to export all of
them or just one by one. By default the export will be printed to the standard output.
If you want you can save your configurations into a file by using ">" as follows:

C<< memento features export all > memento_all.cfg >>

=item I<import [--file]>

Import your features using a previously exported config file. You can choose to
import all of them or just one by one. Use B<--file> option to specify the file
path (in direct input mode), otherwise memento will remember you to specify it
later (progressive input mode):

C<< memento features import git --file memento_all.cfg >>

=back



=head1 GIT

I<memento git> is a configurable tool with the main purpose to help developers
creating branches, following git-flow-like (but divergent) flows. This is not a
wrapper around git core features, but just something like an extension.

I<memento git> provides the following operations:

=over 2

=item I<config>

Manages Memento Git configurations providing the following operations:

=over 2

=item I<init [--project]>

Initialize your git repository storing configurations that will be used for
branches creation, project name configuration and git hooks management.
Use B<--project> option to specify a project name.

=item I<list>

Lists all Memento Git configurations.

=item I<delete>

Delete all Memento Git configurations affecting your current repository.

=back

=item I<root>

Utility command used to show the repository root.

=item I<start [issue-id] [--source]>

Creates a new branch starting from the configured source branch. Use B<--source>
option to override the default one. If during the configuration operation, the
Issue Tracker support was enabled, you will be asked to insert an Issue Id, or you
can provide it inline I<memento git start [issue-id]>. It will be
used to build the new branch, following the configured branch pattern.
Via the I<workflow> tool, is possible to create a rule for updating issue status
and done ratio on git flow start, automatically assigning it to current user, and
optionally add a comment.

=item I<finish [--safe] [--silent]>

Use this command to merge current branch into the configure B<destination> branch.
Current branch will also be deleted if the B<delete> configuration has been set.
If you are not familiar with this command, use the B<--safe> option to avoid
unwanted behaviors (you will be asked to confirm destination and deletion options).
Via the I<workflow> tool, is possible to create a rule for updating issue status
and done ratio on git flow finish and optionally add a comment.
If you want to avoid execution of B<git flow finish> events, run this command with
the B<--silent> option. Your code will be merged into the destination branch but
no other action will be performed (eg: time traker or issue traker actions).

=item I<pause>

If you have enabled a Time Tracker, use this command to pause the timer and log
your worked hours. This will not affect your code but will only handle time entries.

=item I<resume>

If you have previously paused your Time Tracker, you can always resume it by using
this command.

=item I<log>

Show the git log tree in a pretty format.

=item I<rebase>

C<< memento git rebase >>

Rebases current branch with the configured source branch.

C<< memento git rebase <branch_name> >>

Rebases current branch with the provided one.

=item I<commit>

Allows you to commit your code by using conventional commits.

=back



=head1 GITLAB

You can easily integrate Memento with multiple instances of Gitlab, with the
I<memento gitlab config add> command, and switch from one to another simply by
using the I<memento gitlab config switch [gitlab_api_id]> command.

I<memento gitlab> provides the following operations:

=over 2

=item I<config>

Manages Gitlab API configurations providing the following options:

=over 2

=item I<add>

Adds a new configurations set for a Gitlab instance.

=item I<delete [gitlab_api_id]>

Deletes a configurations set for a Gitlab instance.

=item I<list>

Lists all Gitlab configurations.

=item I<switch [gitlab_api_id]>

Sets a Gitlab instance as the default one. All queries will be executed to the
default one. Otherwise, you can change on the fly the active Gitlab instance by
using the B<--api-id> option, for each memento gitlab command.

=back

=item I<issue [gitlab_issue_iid [--open]]>

Shows the details of an issue. If the B<--open> boolean option has been provided,
the issue will not be rendered, but opened into your default web browser.

=item I<projects>

Renders a table containing info about all available Gitlab projects.

=item I<user>

Renders a table containing info about current user referring to the active api.

=back



=head1 TAIGA

You can easily integrate Memento with multiple instances of Taiga, with the
I<memento taiga config add> command, and switch from one to another simply by
using the I<memento taiga config switch [taiga_api_id]> command.

I<memento taiga> provides the following operations:

=over 2

=item I<config>

Manages Taiga API configurations providing the following options:

=over 2

=item I<add>

Adds a new configurations set for a Taiga instance.

=item I<delete [taiga_api_id]>

Deletes a configurations set for a Taiga instance.

=item I<list>

Lists all Taiga configurations.

=item I<switch [taiga_api_id]>

Sets a Taiga instance as the default one. All queries will be executed to the
default one. Otherwise, you can change on the fly the active Taiga instance by
using the B<--api-id> option, for each memento taiga command.

=back

=item I<issue [task|issue]/[taiga_issue_id [--open]]>

Shows the details of an issue or task. If the B<--open> boolean option has been
provided, the issue will not be rendered, but opened into your default web browser.

=item I<projects>

Renders a table containing info about all available Taiga projects.

=item I<user>

Renders a table containing info about current user referring to the active api.

=back



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


=head1 JIRA

You can easily integrate Memento with multiple instances of Jira, with the
I<memento jira config add> command, and switch from one to another simply by
using the I<memento jira config switch [jira_api_id]> command.

I<memento jira> provides the following operations:

=over 2

=item I<config>

Manages Jira API configurations providing the following options:

=over 2

=item I<add>

Adds a new configurations set for a Jira instance.

=item I<delete [jira_api_id]>

Deletes a configurations set for a Jira instance.

=item I<list>

Lists all Jira configurations.

=item I<switch [jira_api_id]>

Sets a Jira instance as the default one. All queries will be executed to the
default one. Otherwise, you can change on the fly the active Jira instance by
using the B<--api-id> option, for each memento jira command.

=back

=item I<issue [jira_issue_id_or_key [--open]]>

Shows the details of an issue. If the B<--open> boolean option has been provided,
the issue will not be rendered, but opened into your default web browser.

=item I<projects>

Renders a table containing info about all available Jira projects.

=item I<search>

Searches for issues using the following options:

=over 2

=item --resolution

Filter by resolution (Unresolved, Done, ...)

=item --assignee

Filter by user key (usually name.surname or the email address chunk before the @)

=item --project

Filter by project KEY

=item --status

Filter by issue status (In progress, Closed, ...)

=item --type

Filter by issue type (Task, Bug, ...)

=back

=item I<user>

Renders a table containing info about current user referring to the active api.

=back



=head1 PAYMO

You can easily integrate Memento with multiple instances of Paymo, with the
I<memento paymo config add> command, and switch from one to another simply by
using the I<memento paymo config switch [paymo_api_id]> command.

I<memento paymo> provides the following operations:

=over 2

=item I<config>

Manages Paymo API configurations providing the following options:

=over 2

=item I<add>

Adds a new configurations set for a Paymo instance.

=item I<delete [paymo_api_id]>

Deletes a configurations set for a Paymo instance.

=item I<list>

Lists all Paymo configurations.

=item I<switch [paymo_api_id]>

Sets a Paymo instance as the default one. All queries will be executed to the
default one. Otherwise, you can change on the fly the active Paymo instance by
using the B<--api-id> option, for each memento paymo command.

=back

=item I<clients>

Renders a table containing info about all available Paymo clients.

=item I<info>

Renders a table containing info about Project Name and Task list bounded to the
current repository.

=item I<projects>

Renders a table containing info about all available Paymo projects.

=item I<setProject>

Allows you to change Project Name and Task list for the current repository.

=item I<users>

Renders a table containing info about all available Paymo users.

=item I<user>

Renders a table containing info about current user referring to the active api.

=back



=head1 TEMPO

You can easily integrate Memento with multiple instances of Tempo, with the
I<memento tempo config add> command, and switch from one to another simply by
using the I<memento tempo config switch [tempo_api_id]> command.

I<memento tempo> provides the following operations:

=over 2

=item I<config>

Manages Tempo API configurations providing the following options:

=over 2

=item I<add>

Adds a new configurations set for a Tempo instance.

=item I<delete [tempo_api_id]>

Deletes a configurations set for a Tempo instance.

=item I<list>

Lists all Tempo configurations.

=item I<switch [tempo_api_id]>

Sets a Tempo instance as the default one. All queries will be executed to the
default one. Otherwise, you can change on the fly the active Tempo instance by
using the B<--api-id> option, for each memento tempo command.

=back

=item I<members>

Renders a table containing info about all available team members.

=item I<teams>

Renders a table containing info about all available teams.

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
default one. Otherwise, you can change on the fly the active Redmine instance by
using the B<--api-id> option, for each memento redmine command.

=back

=item I<issue [redmine_issue_id [--open]]>

Shows the details of an issue. If the B<--open> boolean option has been provided,
the issue will not be rendered, but opened into your default web browser.

=item I<projects>

Renders a table containing info about all available Redmine projects.

=item I<queries>

Renders a table containing info about all available Redmine custom queries.

=item I<query [redmine_query_id]>

Renders a table containing info about all available Redmine issue extracted from
the custom query.

=item I<user>

Renders a table containing info about current user referring to the active api.

=back



=head1 SCHEMA

I<memento schema> is the automatic update manager for Memento codebase.

It provides the following operations:

=over 2

=item I<check>

Check, for code updates automatically, with the frequency specified via config.

Insert I<memento schema check> entry into your bash profile in order to
automatically execute the command whenever you open a new terminal window.

=item I<config>

Manages Memento schema configurations, allowing user to enable/disable automatic
updates or to set frequency of update check.

=back



=head1 WORKFLOW

I<memento workflow> is the dedicated tool for workflows management.

It provides the following operations:

=over 2

=item I<rules>

Add, delete and list workflow rules in order to create event driven automations.

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

Copyright (c) 2015 - 2020 Adriano Cori. All rights reserved.
This program is free software; you can redistribute
it and/or modify it under the terms of the GPL2 license.

The full text of the license can be found in the
LICENSE file included with this module.

=head1 AUTHOR

Bonsaimeme S.r.l. <http://www.bmeme.com>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2105 - 2020 by Adriano Cori and Bonsaimeme S.r.l.

This is free software, licensed under:

  The GPL2 License

=cut
