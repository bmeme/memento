NAME

    memento

VERSION

    version 1.12.4

SYNOPSIS

    memento [TOOL [COMMAND [COMMAND_ARG1 ...]]] [--OPTIONS
    [--MORE_OPTIONS]]

DESCRIPTION

    memento is a modular step by step command line tool. By default it
    provides the following commands:

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
    required argument is missing. For example you can get your last
    executed command via direct input:

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

    If you want to extend Memento with your own tools, put them into
    Memento/Tool/custom directory. The best tools will be added into
    Memento core tools, so feel free to send us your tool!

INSTALLATION

    In order to be able to manage third party perl modules Memento requires
    cpan (http://www.cpan.org/).

    Open a terminal and execute the install.pl file located into memento
    dir:

    ./install.pl

    On Ubuntu

      Before install Memento, be sure to have perl-doc and
      libwww-curl-perl:

      sudo apt-get install perl-doc

      sudo apt-get install libwww-curl-perl

      sudo ./install.pl

AFTER INSTALL

    After install process has ended please add the following lines, also
    shown by the install script to your .bashrc or .zshrc file:

    memento schema check

    source <memento-install-dir>/misc/completion.sh

 ENVIRONMENT VARIABLES

    Memento uses the following environment variables which can be used
    following your needs:

      - MEMENTO_HTTP_TIMEOUT: a number which defines the HTTP request timeout.
      - MEMENTO_SYSTEM_COLOR: the text color used to highlight system commands.
      Please take a look at https://metacpan.org/pod/Term::ANSIColor for correct
      usage.

    export MEMENTO_HTTP_TIMEOUT="20"

    export MEMENTO_HTTP_TIMEOUT="bold magenta"

ACTIVITY

    memento activity is a configurable tool which will help you keeping
    track of your activities progression and the time spent on it. If you
    want you can configure it so that you can use it in conjunction with an
    issue tracker and a time tracker.

    memento activity provides the following operations:

    config

      Manages Memento Activity configurations providing the following
      operations:

      init [--project]

	Initialize your Activity configurations that will be used for
	defining which issue tracker and / or time tracker will be used.

      list

	Lists all Memento Activity configurations.

      delete

	Delete all Memento Activity configurations.

    start [issue-id] [--issue-tracker] [--time-tracker] [--manual]

      Starts a new activity. Use --manual option if you don't need to use
      an Issue Tracker. If during the configuration operation, the Issue
      Tracker support was enabled, you will be asked to insert an Issue Id,
      or you can provide it inline memento activity start [issue-id]. It
      will be used to extract the activity name from the issue and to
      change the its status. Via the workflow tool, it's possible to create
      a rule for updating issue status and done ratio on activity start,
      automatically assigning it to current user, and optionally add a
      comment.

    stop

      Use this command when you've to stop working on your activity. Via
      the workflow tool, it's possible to create a rule for updating issue
      status and done ratio on activity stop and optionally add a comment.

    resume

      If you have previously stopped your activity, you can always resume
      it by using this command.

    current [--open]

      You can view what's your current activity by using this command. If
      you wanna open it in your browser, then use the --open option.

BITBUCKET

    Due to its API limitations, Bitbucket issue tracker can only be used
    for branch naming generation. No change issue status or assignee
    neither comments creation operations can be done.

    You can easily integrate Memento with multiple instances of Bitbucket,
    with the memento bitbucket config add command, and switch from one to
    another simply by using the memento bitbucket config switch
    [bitbucket_api_id] command.

    memento bitbucket provides the following operations:

    config

      Manages Bitbucket API configurations providing the following options:

      add

	Adds a new configurations set for a Bitbucket instance.

      delete [bitbucket_api_id]

	Deletes a configurations set for a Bitbucket instance.

      list

	Lists all Bitbucket configurations.

      switch [bitbucket_api_id]

	Sets a Bitbucket instance as the default one. All queries will be
	executed to the default one. Otherwise, you can change on the fly
	the active Bitbucket instance by using the --api-id option, for
	each memento bitbucket command.

    issue [bitbucket_issue_id [--open]]

      Shows the details of an issue. If the --open boolean option has been
      provided, the issue will not be rendered, but opened into your
      default web browser.

    projects

      Renders a table containing info about all available Bitbucket
      projects.

    user

      Renders a table containing info about current user referring to the
      active api.

FEATURES

    memento features allows you to export and import all your tools
    configurations.

    It provides the following operations:

    export

      Export configurations of your tools (features). You can choose to
      export all of them or just one by one. By default the export will be
      printed to the standard output. If you want you can save your
      configurations into a file by using ">" as follows:

      memento features export all > memento_all.cfg

    import [--file]

      Import your features using a previously exported config file. You can
      choose to import all of them or just one by one. Use --file option to
      specify the file path (in direct input mode), otherwise memento will
      remember you to specify it later (progressive input mode):

      memento features import git --file memento_all.cfg

GIT

    memento git is a configurable tool with the main purpose to help
    developers creating branches, following git-flow-like (but divergent)
    flows. This is not a wrapper around git core features, but just
    something like an extension.

    memento git provides the following operations:

    config

      Manages Memento Git configurations providing the following
      operations:

      init [--project]

	Initialize your git repository storing configurations that will be
	used for branches creation, project name configuration and git
	hooks management. Use --project option to specify a project name.

      list

	Lists all Memento Git configurations.

      delete

	Delete all Memento Git configurations affecting your current
	repository.

    root

      Utility command used to show the repository root.

    start [issue-id] [--source]

      Creates a new branch starting from the configured source branch. Use
      --source option to override the default one. If during the
      configuration operation, the Issue Tracker support was enabled, you
      will be asked to insert an Issue Id, or you can provide it inline
      memento git start [issue-id]. It will be used to build the new
      branch, following the configured branch pattern. Via the workflow
      tool, is possible to create a rule for updating issue status and done
      ratio on git flow start, automatically assigning it to current user,
      and optionally add a comment.

    finish [--safe] [--silent]

      Use this command to merge current branch into the configure
      destination branch. Current branch will also be deleted if the delete
      configuration has been set. If you are not familiar with this
      command, use the --safe option to avoid unwanted behaviors (you will
      be asked to confirm destination and deletion options). Via the
      workflow tool, is possible to create a rule for updating issue status
      and done ratio on git flow finish and optionally add a comment. If
      you want to avoid execution of git flow finish events, run this
      command with the --silent option. Your code will be merged into the
      destination branch but no other action will be performed (eg: time
      traker or issue traker actions).

    pause

      If you have enabled a Time Tracker, use this command to pause the
      timer and log your worked hours. This will not affect your code but
      will only handle time entries.

    resume

      If you have previously paused your Time Tracker, you can always
      resume it by using this command.

    log

      Show the git log tree in a pretty format.

    rebase

      memento git rebase

      Rebases current branch with the configured source branch.

      memento git rebase <branch_name>

      Rebases current branch with the provided one.

    commit

      Allows you to commit your code by using conventional commits.

GITLAB

    You can easily integrate Memento with multiple instances of Gitlab,
    with the memento gitlab config add command, and switch from one to
    another simply by using the memento gitlab config switch
    [gitlab_api_id] command.

    memento gitlab provides the following operations:

    config

      Manages Gitlab API configurations providing the following options:

      add

	Adds a new configurations set for a Gitlab instance.

      delete [gitlab_api_id]

	Deletes a configurations set for a Gitlab instance.

      list

	Lists all Gitlab configurations.

      switch [gitlab_api_id]

	Sets a Gitlab instance as the default one. All queries will be
	executed to the default one. Otherwise, you can change on the fly
	the active Gitlab instance by using the --api-id option, for each
	memento gitlab command.

    issue [gitlab_issue_iid [--open]]

      Shows the details of an issue. If the --open boolean option has been
      provided, the issue will not be rendered, but opened into your
      default web browser.

    projects

      Renders a table containing info about all available Gitlab projects.

    user

      Renders a table containing info about current user referring to the
      active api.

TAIGA

    You can easily integrate Memento with multiple instances of Taiga, with
    the memento taiga config add command, and switch from one to another
    simply by using the memento taiga config switch [taiga_api_id] command.

    memento taiga provides the following operations:

    config

      Manages Taiga API configurations providing the following options:

      add

	Adds a new configurations set for a Taiga instance.

      delete [taiga_api_id]

	Deletes a configurations set for a Taiga instance.

      list

	Lists all Taiga configurations.

      switch [taiga_api_id]

	Sets a Taiga instance as the default one. All queries will be
	executed to the default one. Otherwise, you can change on the fly
	the active Taiga instance by using the --api-id option, for each
	memento taiga command.

    issue [task|issue]/[taiga_issue_id [--open]]

      Shows the details of an issue or task. If the --open boolean option
      has been provided, the issue will not be rendered, but opened into
      your default web browser.

    projects

      Renders a table containing info about all available Taiga projects.

    user

      Renders a table containing info about current user referring to the
      active api.

HISTORY

    Every command executed is logged into the memento history and can be
    bookmarked as a shortcut.

    memento history provides the following operations:

    bookmark

      Bookmarks a command creating a new shortcut.

    bookmarks

      Lists all available bookmarks.

    clear

      Clear the command history.

    exec

      Executes a command previously logged into the command history.

    last [--execute]

      Get last executed command. Use --execute option to execute it.

    list

      Lists all commands logged into the command history.

    unbookmark

      Deletes a bookmarked command.

JIRA

    You can easily integrate Memento with multiple instances of Jira, with
    the memento jira config add command, and switch from one to another
    simply by using the memento jira config switch [jira_api_id] command.

    memento jira provides the following operations:

    config

      Manages Jira API configurations providing the following options:

      add

	Adds a new configurations set for a Jira instance.

      delete [jira_api_id]

	Deletes a configurations set for a Jira instance.

      list

	Lists all Jira configurations.

      switch [jira_api_id]

	Sets a Jira instance as the default one. All queries will be
	executed to the default one. Otherwise, you can change on the fly
	the active Jira instance by using the --api-id option, for each
	memento jira command.

    issue [jira_issue_id_or_key [--open]]

      Shows the details of an issue. If the --open boolean option has been
      provided, the issue will not be rendered, but opened into your
      default web browser.

    projects

      Renders a table containing info about all available Jira projects.

    search

      Searches for issues using the following options:

      --resolution

	Filter by resolution (Unresolved, Done, ...)

      --assignee

	Filter by user key (usually name.surname or the email address chunk
	before the @)

      --project

	Filter by project KEY

      --status

	Filter by issue status (In progress, Closed, ...)

      --type

	Filter by issue type (Task, Bug, ...)

    user

      Renders a table containing info about current user referring to the
      active api.

PAYMO

    You can easily integrate Memento with multiple instances of Paymo, with
    the memento paymo config add command, and switch from one to another
    simply by using the memento paymo config switch [paymo_api_id] command.

    memento paymo provides the following operations:

    config

      Manages Paymo API configurations providing the following options:

      add

	Adds a new configurations set for a Paymo instance.

      delete [paymo_api_id]

	Deletes a configurations set for a Paymo instance.

      list

	Lists all Paymo configurations.

      switch [paymo_api_id]

	Sets a Paymo instance as the default one. All queries will be
	executed to the default one. Otherwise, you can change on the fly
	the active Paymo instance by using the --api-id option, for each
	memento paymo command.

    clients

      Renders a table containing info about all available Paymo clients.

    info

      Renders a table containing info about Project Name and Task list
      bounded to the current repository.

    projects

      Renders a table containing info about all available Paymo projects.

    setProject

      Allows you to change Project Name and Task list for the current
      repository.

    users

      Renders a table containing info about all available Paymo users.

    user

      Renders a table containing info about current user referring to the
      active api.

TEMPO

    You can easily integrate Memento with multiple instances of Tempo, with
    the memento tempo config add command, and switch from one to another
    simply by using the memento tempo config switch [tempo_api_id] command.

    memento tempo provides the following operations:

    config

      Manages Tempo API configurations providing the following options:

      add

	Adds a new configurations set for a Tempo instance.

      delete [tempo_api_id]

	Deletes a configurations set for a Tempo instance.

      list

	Lists all Tempo configurations.

      switch [tempo_api_id]

	Sets a Tempo instance as the default one. All queries will be
	executed to the default one. Otherwise, you can change on the fly
	the active Tempo instance by using the --api-id option, for each
	memento tempo command.

    members

      Renders a table containing info about all available team members.

    teams

      Renders a table containing info about all available teams.

REDMINE

    You can easily integrate Memento with multiple instances of Redmine,
    with the memento redmine config add command, and switch from one to
    another simply by using the memento redmine config switch
    [redmine_api_id] command.

    memento redmine provides the following operations:

    config

      Manages Redmine API configurations providing the following options:

      add

	Adds a new configurations set for a Redmine instance.

      delete [redmine_api_id]

	Deletes a configurations set for a Redmine instance.

      list

	Lists all Redmine configurations.

      switch [redmine_api_id]

	Sets a Redmine instance as the default one. All queries will be
	executed to the default one. Otherwise, you can change on the fly
	the active Redmine instance by using the --api-id option, for each
	memento redmine command.

    issue [redmine_issue_id [--open]]

      Shows the details of an issue. If the --open boolean option has been
      provided, the issue will not be rendered, but opened into your
      default web browser.

    projects

      Renders a table containing info about all available Redmine projects.

    queries

      Renders a table containing info about all available Redmine custom
      queries.

    query [redmine_query_id]

      Renders a table containing info about all available Redmine issue
      extracted from the custom query.

    user

      Renders a table containing info about current user referring to the
      active api.

SCHEMA

    memento schema is the automatic update manager for Memento codebase.

    It provides the following operations:

    check

      Check, for code updates automatically, with the frequency specified
      via config.

      Insert memento schema check entry into your bash profile in order to
      automatically execute the command whenever you open a new terminal
      window.

    config

      Manages Memento schema configurations, allowing user to
      enable/disable automatic updates or to set frequency of update check.

WORKFLOW

    memento workflow is the dedicated tool for workflows management.

    It provides the following operations:

    rules

      Add, delete and list workflow rules in order to create event driven
      automations.

USAGE

    memento [-OPTIONS [-MORE_OPTIONS]] [--] [PROGRAM_ARG1 ...]

    The following single-character options are accepted: Boolean (without
    arguments): -v -h

    Options may be merged together. -- stops processing of options.

BUGS

    None known as of release, but...

AUTHOR

    Adriano Cori <adriano.cori@bmeme.com>

COPYRIGHT

    Copyright (c) 2015 - 2021 Adriano Cori. All rights reserved. This
    program is free software; you can redistribute it and/or modify it
    under the terms of the GPL2 license.

    The full text of the license can be found in the LICENSE file included
    with this module.

AUTHOR

    Bonsaimeme S.r.l. <http://www.bmeme.com>

COPYRIGHT AND LICENSE

    This software is Copyright (c) 2105 - 2021 by Adriano Cori and
    Bonsaimeme S.r.l.

    This is free software, licensed under:

      The GPL2 License

