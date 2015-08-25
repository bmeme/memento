NAME
    memento

VERSION
    version 0.3.2

SYNOPSIS
    memento [-OPTIONS [-MORE_OPTIONS]] [--] [PROGRAM_ARG1 ...]

    The following single-character options are accepted: Boolean (without
    arguments): --version --help

DESCRIPTION
    memento is a modular step by step command line tool. By default it
    provides three types of commands:

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

HISTORY
    Every command executed is logged into the memento history and can be
    bookmarked as a shortcut.

    *memento history* provides the following operations:

    *bookmark*
      Bookmarks a command creating a new shortcut.

    *bookmarks*
      Lists all available bookmarks.

    *clear*
      Clear the command history.

    *exec*
      Executes a command previously logged into the command history.

    *last [--execute]*
      Get last executed command. Use --execute option to execute it.

    *list*
      Lists all commands logged into the command history.

    *unbookmark*
      Deletes a bookmarked command.

REDMINE
    You can easily integrate Memento with multiple instances of Redmine,
    with the *memento redmine config add* command, and switch from one to
    another simply by using the *memento redmine config switch
    [redmine_api_id]* command.

    *memento redmine* provides the following operations:

    *config*
      Manages Redmine API configurations providing the following options:

      *add*
        Adds a new configurations set for a Redmine instance.

      *delete [redmine_api_id]*
        Deletes a configurations set for a Redmine instance.

      *list*
        Lists all Redmine configurations.

      *switch [redmine_api_id]*
        Sets a Redmine instance as the default one. All queries will be
        executed to the default one.

    *issue [redmine_issue_id [--open]]*
      Shows the details of an issue. If the --open boolean option has been
      provided, the issue sill not be rendered, but opened into your default
      web browser.

    *projects*
      Renders a table containing info about all available Redmine projects.

    *queries*
      Renders a table containing info about all available Redmine custom
      queries.

    *query [redmine_query_id]*
      Renders a table containing info about all available Redmine issue
      extracted from the custom query.

GIT
    *memento git* is a configurable tool with the main purpose to help
    developers creating branch, following git-flow-like (but divergent)
    flows. This is not a wrapper around git core features, but just
    something like an extension.

    *memento git* provides the following operations:

    *branch [--source]*
      Creates a new branch starting from the configured source branch. Use
      --source option to override the default one. If during the
      configuration operation, the Redmine support was enabled, you will be
      asked to insert a Redmine Issue Id. It will be used to build the new
      branch, following the configured branch pattern.

    *config*
      Manages Memento Git configurations providing the following options:

    *init*
      Initialize your git repository storing configurations that will be
      used for branches creation.

    *list*
      Lists all Memento Git configurations.

    *delete*
      Delete all Memento Git configurations affecting your current
      repository.

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
    Copyright (c) 2015 Adriano Cori. All rights reserved. This program is
    free software; you can redistribute it and/or modify it under the terms
    of the GPL2 license.

    The full text of the license can be found in the LICENSE file included
    with this module.

AUTHOR
    Bonsaimeme S.r.l. <http://www.bmeme.com>

COPYRIGHT AND LICENSE
    This software is Copyright (c) 2105 by Adriano Cori and Bonsaimeme
    S.r.l.

    This is free software, licensed under:

      The GPL2 License

