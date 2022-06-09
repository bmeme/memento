#!/usr/bin/env perl
require "$root/Daemon.pm";
require "$root/Memento/Command.pm";

package Memento::Tool::git;

use feature 'say';
our @ISA = qw(Memento::Command);
use strict; use warnings;
use Cwd;
use File::Copy qw(copy);
use Getopt::Long;
use Switch;
use Text::Trim;
use Data::Dumper;

our ($cwd);
$cwd = getcwd();

sub config {
  my $class = shift;
  my $op = shift;

  if (!$op) {
    $op = Daemon::prompt("Choose an operation", undef, ['init', 'list', 'delete']);
  }

  switch ($op) {
    case 'init' {
      $class->_check_repository();

      my $default = $class->_get_config(1);
      say "Please answer the following questions (press enter to confirm defaults)\n";

      GetOptions(
        'project=s' => \$default->{project}
      ) or die 'Incorrect usage';

      Daemon::printLabel("Project");
      my $project = $default->{project} ? $default->{project} : Daemon::current_dir_name();
      my $p_name = Daemon::prompt("Set/confirm current project name", $project);

      say "";
      Daemon::printLabel("Branch configurations");
      my @branches = $class->_get_branches();
      my @source_branches = @branches;
      shift @source_branches;
      unshift @source_branches, '@self';
      my $source = Daemon::prompt('Specify source branch for "memento git start"', $default->{branch}->{source}, [@source_branches]);
      my $destination = Daemon::prompt('Specify destination branch for "memento git finish"', $default->{branch}->{destination}, [@branches]);
      $destination = ($destination eq '<none>') ? 0 : $destination;

      my $delete = Daemon::prompt('Do you want to automatically delete the new branch after "memento git finish"?', 'no', ['no', 'local', 'remote + local']);
      $delete = ($delete eq 'no') ? 0 : (($delete eq 'local') ? 1 : 2);

      my $tracker = 0;
      my @api_id_names;
      my $tracker_config;

      my $issue_tracker = 0;
      my $issue_tracker_id = 0;
      if (Daemon::prompt('Do you want to enable Issue Tracker support?', 'yes', ['yes', 'no']) eq 'yes') {
        $issue_tracker = Daemon::prompt('Choose an Issue Tracker', $default->{issue_tracker}, $class->_get_issue_trackers());
        $tracker = Memento::Tool->instantiate($issue_tracker);

        if (!$default->{branch}->{pattern}) {
          $default->{branch}->{pattern} = $tracker->_branch_pattern();
        }

        @api_id_names = $tracker->_get_api_id_names();
        $tracker_config = $tracker->_get_config();
        $issue_tracker_id = Daemon::prompt('Select an account', $tracker_config->{default}, @api_id_names);
      }
      my $pattern = $issue_tracker ? Daemon::prompt('Please specify your branch naming convention (you can use issue properties as tokens)', $default->{branch}->{pattern}) : 0;

      say "";
      my $time_tracker = 0;
      my $time_tracker_id = 0;
      if (Daemon::prompt('Do you want to enable Time Tracker support?', 'yes', ['yes', 'no']) eq 'yes') {
        $time_tracker = Daemon::prompt('Choose a Time Tracker', $default->{time_tracker}, $class->_get_time_trackers());

        $tracker = Memento::Tool->instantiate($time_tracker);
        @api_id_names = $tracker->_get_api_id_names();
        $tracker_config = $tracker->_get_config();
        $time_tracker_id = Daemon::prompt('Select an account', $tracker_config->{default}, @api_id_names);
      }

      say "";
      Daemon::printLabel("Git Hooks");
      my $commit_validation = 0;
      if (Daemon::prompt("Do you want to set a validation for your commit messages?", 'no', ['yes', 'no']) eq 'yes') {
        $commit_validation = Daemon::prompt('Enter regex to be used as commit validation (without leading and trailing slashes)', $default->{hooks}->{commit_msg});
        $commit_validation = quotemeta($commit_validation);
      }

      my $pre_commit = (Daemon::prompt("Do you want to enable 'pre commit' events for this project?", 'no', ['yes', 'no']) eq 'yes') ? 1 : 0;

      my $post_commit_notify = 0;
      if ($issue_tracker && (Daemon::prompt("Do you want to enable $issue_tracker notifications after each commit?", 'no', ['yes', 'no']) eq 'yes')) {
        $post_commit_notify = 1;
      }

      my $config = {
        project => $p_name,
        branch => {
          source => $source,
          destination => $destination,
          delete => $delete,
          pattern => $pattern
        },
        hooks => {
          commit_msg => $commit_validation,
          pre_commit => $pre_commit,
          post_commit => $post_commit_notify
        },
        issue_tracker => $issue_tracker,
        issue_tracker_id => $issue_tracker_id,
        time_tracker => $time_tracker,
        time_tracker_id => $time_tracker_id
      };

      say Daemon::array2table('Memento Git configurations', [$config], {full_nested => 1});

      if (Daemon::prompt('Do you confirm these configurations?', 'yes', ['yes', 'no']) eq 'yes') {
        if ($default->{project}) {
          $class->_delete_config();
        }
        $class->_save_config($config);
        say "Your Memento Git configurations have been saved!\n";
      }
    }
    case 'list' {
      say Daemon::array2table("Git Configurations", [$class->_get_config()], {full_nested => 1});
    }
    case 'delete' {
      $class->_delete_config();
      say "Your Memento Git configurations have been deleted.";
    }
  }
}

sub log {
  Daemon::system("git log --pretty=format:\"%h %ad | %s%d [%an]\" --graph --date=short");
}

sub root {
  my $class = shift;
  my $goto = shift || 0;
  my $p_root = `git rev-parse --show-toplevel 2>/dev/null`;
  chomp($p_root);

  if ($goto && $p_root) {
    chdir $p_root;
  }
  else {
    return $p_root;
  }
}

sub start {
  my $class = shift;
  my $id = shift || 0;
  my $config = $class->_get_config();
  my $branch;
  my @branches = $class->_get_branches();
  my $source = $config->{branch}->{source};
  chomp($source);

  GetOptions(
    'source=s' => \$source
  ) or die 'Incorrect usage';

  # Reset $id to 0 if an option has been passed but not an ID.
  if ($id =~ /^--/) {
    $id = 0;
  }

  my $current_branch = $class->_get_current_branch();
  if ($source eq '@self') {
    $source = $current_branch;
  }

  if (!Daemon::in_array([@branches], $source)) {
    Daemon::system("git fetch");
    # Let's try checking among remote branches before saying that the specified
    # source branch is not valid.
    @branches = $class->_get_branches(1);
    my $remote_source = 'remotes/' . $class->_get_remote() . '/' . $source;
    if (!Daemon::in_array([@branches], $remote_source)) {
      die "You have specified an invalid source branch: $source\n";
    }

    # Checkout to source branch in order to sync the local repo.
    Daemon::system("git checkout $source");
    # Go back to previous branch.
    Daemon::system("git checkout $current_branch");
  }

  my $issue;

  if ($config->{issue_tracker}) {
    my $issue_tracker = $config->{issue_tracker};

    # Check if the issue tracker has been instantiated. This may happen when
    # executing a Memento git command before having initialized Memento git.
    if (!$class->{$issue_tracker}) {
      $class->{$issue_tracker} = Memento::Tool->instantiate($issue_tracker);
    }

    if (!$id) {
      $id = Daemon::prompt("Enter $issue_tracker issue id");
    }
    $issue = $class->{$issue_tracker}->_get_issue($id);
    if (!$issue) {
      die "You have specified an invalid issue id.";
    }

    my $source_branch = Daemon::printColor($source, "black on_bright_yellow");
    say "You are going to create a new branch, starting from $source_branch, for the following issue:\n";
    $class->{$issue_tracker}->_render_issue($issue);
    if (Daemon::prompt("Do you confirm?", 'yes', ['yes', 'no']) eq 'no') {
      die "Aborting...\n";
    }

    $branch = trim $config->{branch}->{pattern};
    $branch =~ s/:(\w+):/$issue->{$1}/g;
    $branch =~ s/:(\w+)-(\w+):/$issue->{$1}->{$2}/;
    $branch =~ s/:(\w+)-(\w+)-(\w+):/$issue->{$1}->{$2}->{$3}/;
    $branch = lc "$branch";
  }
  else {
    $branch = Daemon::prompt("Enter the branch name");
  }

  $branch = $class->_check_branch_name($branch, $issue);

  if (($branch eq $current_branch) && (Daemon::prompt("New branch and current branch are the same. Continue anyway?", 'no', ['yes', 'no']) eq 'no')) {
    die "Now exiting.\n";
  }

  if (Daemon::in_array([@branches], $branch)) {
    # Checkout to existing branch.
    Daemon::system("git checkout $branch");
  }
  else {
    # Update source branch.
    my $remote = $class->_get_remote();
    Daemon::system("git checkout $source");
    if ($remote) {
      Daemon::system("git pull $remote $source --rebase");
    }
    # Create a new branch from the specified source.
    Daemon::system("git checkout -b $branch $source");
  }

  # Store source branch.
  my $storage = $class->_get_storage();
  $storage->{$branch}->{source} = $source;
  $class->_save_storage($storage);

  $class->_on('git_flow_start', {branch => $branch, issue => $issue});
}

sub pause {
  my $class = shift;
  my $branch = $class->_get_current_branch();
  my $issue = $class->_get_issue();
  $class->_on('git_flow_pause', {branch => $branch, issue => $issue});
}

sub resume {
  my $class = shift;
  my $branch = $class->_get_current_branch();
  my $issue = $class->_get_issue();
  $class->_on('git_flow_resume', {branch => $branch, issue => $issue});
}

sub finish {
  my $class = shift;
  my $config = $class->_get_config();
  my $destination = $config->{branch}->{destination};
  my $delete = $config->{branch}->{delete};
  my $branch = $class->_get_current_branch();
  my $remote = $class->_get_origin_url() ? $class->_get_remote() : 0;
  my $issue = $class->_get_issue();

  my $safe = 0;
  my $silent = 0;
  GetOptions(
    'safe!' => \$safe,
    'silent!' => \$silent
  ) or die 'Incorrect usage';

  if ($safe) {
    my @branches = $class->_get_branches();
    my $delete_modes = ['no', 'local', 'remote + local'];
    my $delete_default = $delete ? @{$delete_modes}[$delete] : 'no';

    $destination = Daemon::prompt('Specify destination branch for merge', $destination, [@branches]);
    $delete = Daemon::prompt("Do you want to delete branch '$branch' after merge?", $delete_default, ['no', 'local', 'remote+local']);
    $delete = ($delete eq 'no') ? 0 : (($delete eq 'local') ? 1 : 2);
  }

  if ($remote) {
    Daemon::system("git push $remote $branch");
  };

  if ($destination ne '0') {
    if ($destination ne $branch) {
      Daemon::system("git checkout $destination");
      if ($remote) {
        Daemon::system("git reset --hard $remote/$destination");
      }
      Daemon::system("git merge $branch");
      if ($remote) {
        Daemon::system("git push $remote $destination");
      }
      if ($delete) {
        Daemon::system("git branch -D $branch");
      }
      if ($remote && ($delete == 2)) {
        Daemon::system("git push $remote :$branch");
      }
    }
    else {
      die "Current branch and destination branch are the same. Cannot proceed.\n";
    }
  }

  if (!$silent) {
    $class->_on('git_flow_finish', {branch => $branch, issue => $issue});
  }
}

sub rebase {
  my $class = shift;
  my $rebase_source = shift || 0;
  my $source = $class->_get_source($rebase_source);
  my $branch = $class->_get_current_branch();
  my $remote = $class->_get_origin_url() ? $class->_get_remote() : 0;
  my $modified_files = $class->_get_modified_files();
  my $source_branch = Daemon::printColor($source, "black on_bright_yellow");

  if ($rebase_source && ($rebase_source ne $source)) {
    say "The configured source branch $source_branch diverges from the one you provided: $rebase_source";
    if (Daemon::prompt("Do you want to continue anyway?", 'no', ['yes', 'no']) eq 'no') {
      die "Aborting...\n";
    }

    $source = $rebase_source;
    $class->_set_source($source);
    $source_branch = Daemon::printColor($source, "black on_bright_yellow");
  }

  say "Now rebasing from $source_branch";

  if (length($modified_files)) {
    Daemon::system("git stash");
  }

  if ($remote) {
    Daemon::system("git fetch");
    Daemon::system("git checkout $source");
    Daemon::system("git pull $remote $source --rebase");
    Daemon::system("git checkout $branch");
  }
  Daemon::system("git rebase $source");

  if (length($modified_files)) {
    Daemon::system("git stash apply");
  }
}

sub source {
  my $class = shift;
  my $source = $class->_get_source();
  my $branch = $class->_get_current_branch();
  my $source_branch = Daemon::printColor($source, "black on_bright_yellow");
  say "Branch $branch has been created starting from $source_branch";
}

sub commit {
  my $class = shift;
  my $issue = $class->_get_issue();
  my $filename = "";
  my $type = Daemon::prompt("Type of commit", 0, [
    'build',
    'ci',
    'chore',
    'docs',
    'feat',
    'fix',
    'improvement',
    'perf',
    'refactor',
    'revert',
    'style',
    'test'
  ]);

  my $scope = "";
  my $color = "black on_bright_yellow";

  Daemon::printLabel("A scope MAY be provided to a commit’s type, to provide additional contextual information. Eg: $type(login): ", $color, 1);
  if (Daemon::prompt("Do you want to add a scope?", 'yes', ['no', 'yes']) eq 'yes') {
    $scope = trim lc Daemon::prompt("Commit scope");
  }

  if ($scope) {
    $scope = "($scope)";
  }

  my $message = "$type$scope: ";
  my $max_length = 72 - length $message;

  print "\n";
  Daemon::printLabel("The description is a short summary of the code changes, e.g., $type$scope: array parsing issue when multiple spaces were contained in string.", $color, 1);
  my $description = trim Daemon::prompt("Commit description", '', 0, $max_length);
  $description =~ s/[\s\.]*?$//;

  my $breaking = "";
  my $body = "";

  print "\n";
  Daemon::printLabel("A longer commit body MAY be provided after the short description, providing additional contextual information about the code changes.", $color, 1);
  if (Daemon::prompt("Do you want to add a body?", 'no', ['no', 'yes']) eq 'yes') {
    Daemon::printLabel("Conventional commits of any type can be API-breaking changes. These changes occasion a major version change (5 to 6, say) in Semantic Versioning.", "white on_magenta", 1);
    $breaking = (Daemon::prompt("Does this commit contain breaking changes?", 'no', ['no', 'yes']) eq 'yes') ? 'BREAKING CHANGE: ' : '';

    $filename = '/tmp/git-commit-body';
    Daemon::write($filename, '', '1', '>');
    Daemon::open_default_editor($filename);
    my @body_content = Daemon::read($filename);
    unlink $filename;
    $body = trim "@body_content";
  }

  my $footer = "";
  if ($issue) {
    my $issue_tracker = Memento::Tool->instantiate($class->_get_config()->{'issue_tracker'});
    my $name = $issue_tracker->_time_tracker_entry($issue);
    $name =~ s/"/\\"/g;
    $name =~ s/'/\\'/g;
    $footer = "refs: $name";
  }

  print "\n";
  Daemon::printLabel("An optional footer MUST contain meta-information about the commit, e.g., related pull-requests, reviewers, breaking changes, with one piece of meta-information per-line.", $color, 1);
  if (Daemon::prompt("Do you want to add a footer message? Info about current activity will be added automatically where possible.", 'no', ['no', 'yes']) eq 'yes') {
    $filename = '/tmp/git-commit-footer';
    Daemon::write($filename, '', '1', '>');
    Daemon::open_default_editor($filename);
    my @footer_content = Daemon::read($filename);
    unlink $filename;
    $footer = "$footer\n@footer_content";
  }

  Daemon::system("git commit -m \"$type$scope: $description\n\n$breaking$body\n\n$footer\"");
}

# OVERRIDDEN METHODS ###########################################################

sub _dependencies {
  my $dependencies = [];

  if (&_is_configured()) {
    my $issue_tracker = trim `git config memento.issue-tracker`;
    if ($issue_tracker) {
      push(@{$dependencies}, $issue_tracker);
    }
  }

  return $dependencies;
}

sub _def_config {
  my $class = shift;
  my $source = _is_configured() ? $class->_get_current_branch() : 0;

  return {
    project => undef,
    branch => {
      source => $source,
      destination => $source,
      delete => 0,
      pattern => 0
    },
    hooks => {
      commit_msg => 0,
      pre_commit => 0,
      post_commit => 0
    },
    issue_tracker => 0,
    issue_tracker_id => 0,
    time_tracker => 0,
    time_tracker_id => 0
  };
}

sub _get_config {
  my $class = shift;
  my $optional = shift;
  my $config;

  if (&_is_configured()) {
    my $source = `git config memento.branch.source`;
    my $destination = `git config memento.branch.destination`;
    my $delete = `git config memento.branch.delete`;
    my $pattern = `git config memento.branch.pattern`;
    my $commit_msg = `git config memento.hooks.commit-msg`;
    my $pre_commit = `git config memento.hooks.pre-commit`;
    my $post_commit = `git config memento.hooks.post-commit`;
    my $issue_tracker = `git config memento.issue-tracker`;
    my $issue_tracker_id = `git config memento.issue-tracker-id`;
    my $time_tracker = `git config memento.time-tracker`;
    my $time_tracker_id = `git config memento.time-tracker-id`;

    chomp($source);
    chomp($destination);
    chomp($delete);
    chomp($pattern);
    chomp($commit_msg);
    chomp($pre_commit);
    chomp($post_commit);
    chomp($issue_tracker);
    chomp($issue_tracker_id);
    chomp($time_tracker);
    chomp($time_tracker_id);

    $config = {
      project => $class->_get_project_name,
      branch => {
        source => $source,
        destination => $destination,
        delete => $delete,
        pattern => $pattern
      },
      hooks => {
        commit_msg => $commit_msg,
        pre_commit => $pre_commit,
        post_commit => $post_commit
      },
      issue_tracker => $issue_tracker,
      issue_tracker_id => $issue_tracker_id,
      time_tracker => $time_tracker,
      time_tracker_id => $time_tracker_id
    };
  }
  elsif (!&_is_configured && $optional) {
    $config = $class->_def_config();
  }
  else {
    if (Daemon::prompt("No Memento git config has been found. Do you want to configure it now?", 'yes', ['yes', 'no']) eq 'yes') {
      $class->config("init");
      return $class->_get_config();
    }
    else {
      die "Aborting...\n";
    }
  }

  return $config;
}

sub _get_git_dir {
  my $class = shift;
  my $dir = '.git';

  $class->_check_repository();

  if (-f $dir) {
    my @content = Daemon::read($dir);
    $dir = $content[0];
    chomp($dir);
    $dir =~ s/^gitdir:\s//g;
  }

  return $class->root() . "/$dir";
}

sub _save_config {
  my $class = shift;
  my $config = shift;

  $class->root(1);
  my $git_dir = $class->_get_git_dir();
  Daemon::write("$git_dir/description", $config->{project}, 1, '>');

  Daemon::system("git config memento.branch.source " . $config->{branch}->{source});
  Daemon::system("git config memento.branch.destination " . $config->{branch}->{destination});
  Daemon::system("git config memento.branch.delete " . $config->{branch}->{delete});
  Daemon::system("git config memento.branch.pattern " . $config->{branch}->{pattern});
  Daemon::system("git config memento.hooks.commit-msg " . $config->{hooks}->{commit_msg});
  Daemon::system("git config memento.hooks.pre-commit " . $config->{hooks}->{pre_commit});
  Daemon::system("git config memento.hooks.post-commit " . $config->{hooks}->{post_commit});
  Daemon::system("git config memento.issue-tracker " . $config->{issue_tracker});
  Daemon::system("git config memento.issue-tracker-id " . $config->{issue_tracker_id});
  Daemon::system("git config memento.time-tracker " . $config->{time_tracker});
  Daemon::system("git config memento.time-tracker-id " . $config->{time_tracker_id});

  # Enable Git Hooks.
  my $git_hooks = Memento::Tool->root() . "/misc/git-hooks.pl";
  my $git_hooks_dir = "$git_dir/hooks";

  Daemon::system("ln -s $git_hooks $git_hooks_dir/commit-msg")  if (!-f "$git_hooks_dir/commit-msg");
  Daemon::system("ln -s $git_hooks $git_hooks_dir/pre-commit") if (!-f "$git_hooks_dir/pre-commit");
  Daemon::system("ln -s $git_hooks $git_hooks_dir/post-commit") if (!-f "$git_hooks_dir/post-commit");

  $class->SUPER::_save_config($config);
  $class->_on('git_config_save', {config => $config});
}

sub _pre {
  my ($class) = @_;
  $class->SUPER::_pre();
  chdir $cwd;
}

# EVENT LISTENERS ##############################################################

sub _on_git_commit_msg {
  my $class = shift;
  my $subject = shift;
  my $event = shift;
  my $params = shift;
  my $config = $class->_get_config();

  if (${$params}->{success} && $config->{hooks}->{commit_msg}) {
    my $validation = $config->{hooks}->{commit_msg};
    $validation =~ s/\\\\/\\/g;
    if (${$params}->{message} !~ /$validation/) {
      push(@{${$params}->{errors}}, "Please respect the commit criteria: /$validation/");
      ${$params}->{success} = 0;
    }
  }
}

# RULES ########################################################################

sub _events {
  return [
    {
      name => 'git_flow_start',
      arguments => [
        'branch',
        'issue'
      ]
    },
    {
      name => 'git_flow_pause',
      arguments => [
        'branch',
        'issue'
      ]
    },
    {
      name => 'git_flow_resume',
      arguments => [
        'branch',
        'issue'
      ]
    },
    {
      name => 'git_flow_finish',
      arguments => [
        'branch',
        'issue'
      ]
    },
    {
     name => 'git_commit_msg',
     arguments => [
       'success',
       'errors',
       'commit_message',
       'branch'
     ]
    },
    {
      name => 'git_pre_commit',
      arguments => [
       'success',
       'errors',
       'branch',
       'commit_files'
      ]
    },
    {
      name => 'git_post_commit',
      arguments => []
    },
    {
      name => 'git_config_save',
      arguments => [
        'config'
      ]
    }
  ];
}

sub _conditions {
  return [
    {
      tool => 'git',
      name => 'git_check_current_project',
      callback => '_check_current_project',
      params => [
        {
          name => 'project',
          label => 'Git Project name'
        }
      ]
    }
  ];
}

sub _check_current_project {
  my $class = shift;
  my $params = shift;
  my $config = $class->_get_config();
  return ($config->{project} eq $params->{project});
}

sub _actions {
  return [
    {
      tool => 'git',
      name => 'git_exec_pre_commit_command',
      callback => '_exec_pre_commit_command',
      arguments => [
        'commit_files'
      ],
      params => [
        {
          name => 'shell_command',
          label => 'Shell command (use $file as placeholder)'
        }
      ]
    }
  ];
}

sub _exec_pre_commit_command {
  my $class = shift;
  my $arguments = shift;
  my $params = shift;
  my $config = $class->_get_config();

  if (${$arguments}->{success} && $config->{hooks}->{pre_commit}) {
    foreach my $file (@{${$arguments}->{commit_files}}) {
      my $command = "$params->{shell_command}";
      $command =~ s/\$file/$file/;
      Daemon::printLabel("▶ $command", "black on_bright_yellow", 1);
      my $result = system("$command");

      if ($result != 0) {
        push(@{${$arguments}->{errors}}, "Errors processing file $file");
        ${$arguments}->{success} = 0;
      }
    }
  }
}

# PRIVATE METHODS ##############################################################

sub _check_repository {
  my $class = shift;
  if (-f '.git' || -d '.git') {
    return 1;
  }

  if (Daemon::prompt('Not a git repository. Would you like to initialize Git for this directory?', 'yes', ['yes', 'no']) eq 'yes') {
    say "Memento will create a standard branch structure executing the following commands:";
    my $git_commands = [
      "git init",
      "git add .",
      "git commit -am 'first commit'",
      "git checkout -b development"
    ];
    Daemon::print_list($git_commands);
    print "\n";

    if (Daemon::prompt('Do you confirm execution?', 'yes', ['yes', 'no']) eq 'yes') {
      foreach my $git_command (@{$git_commands}) {
        Daemon::system($git_command);
      }
      say "Git repository initialized.\n";
    }
    else {
      die "Aborting...\n";
    }
  }
  else {
    die "Aborting...\n";
  }
}

sub _check_branch_name {
  my $class = shift;
  my $branch = shift or die "Missing branch to check.\n";
  my $issue = shift;
  my $config = $class->_get_config();

  $branch =~ /^(feature|[\w\-\s]+)\//;
  my $prefix = $1 ? $1 : "feature";

  $branch =~ s/^$prefix\///g;
  $branch = Daemon::machine_name($branch);

  # since whitespaces can be used, converts anything different from the pattern.
  $prefix =~ s/[^\w\-]+/-/g;

  if ($config->{issue_tracker}) {
    my $issue_tracker = $config->{issue_tracker};
    $prefix = $class->{$issue_tracker}->_fix_branch_prefix($prefix, $issue);
    $branch = $class->{$issue_tracker}->_fix_branch_name($branch, $issue);
  }

  $branch = "$prefix/$branch";
  return $branch;
}

sub _delete_config {
  my $class = shift;
  my $git_dir = $class->_get_git_dir() or die "Cannot find git project root";
  my $git_hooks = Memento::Tool->root() . "/misc/git-hooks.pl";

  # Delete memento git configurations if exist.
  if (&_is_configured()) {
    Daemon::system("git config --remove-section memento.branch");
    Daemon::system("git config --remove-section memento.hooks");
    Daemon::system("git config --remove-section memento");
  }

  # Delete git hooks symlinks if exist.
  my $git_hooks_dir = "$git_dir/hooks";
  my @hooks = ('commit-msg', 'pre-commit', 'post-commit');

  foreach my $hook (@hooks) {
    my $link = "$git_hooks_dir/$hook";
    if (-l $link){
      my $symlink = readlink($link);
      if ($symlink eq $git_hooks) {
        unlink $link or die "Failed to remove file $link: $!\n";
      }
    }
  }
}

sub _get_branches {
  my $class = shift;
  my $all = shift || 0;
  my $branch_list = $all ? trim `git branch -a` : trim `git branch`;
  $branch_list =~ s/\* //;
  my @branches = split(' ', $branch_list);
  unshift @branches, '<none>';
  return @branches;
}

sub _get_current_branch {
  my $branch = `git rev-parse --abbrev-ref HEAD`;
  chomp($branch);
  if (!$branch) {
    die "Cannot get current branch.\n";
  }
  return $branch;
}

sub _get_commit_sha {
  my $sha = `git rev-parse HEAD`;
  chomp($sha);
  return $sha;
}

sub _get_updates {
  my $class = shift;
  my $dir = shift || 0;
  if ($dir) {
    chdir $dir;
  }
  my $remote = $class->_get_remote();
  my $branch = $class->_get_current_branch();
  my @updates = `git log HEAD..$remote/$branch --oneline`;
  chomp(@updates);
  return @updates;
}

sub _get_pretty_commit_message {
  my $message = `git log -1 --oneline --pretty`;
  chomp($message);
  return $message;
}

sub _get_last_commit_message {
  my $message = `git log -1 --pretty=%B`;
  chomp($message);
  return $message;
}

sub _get_remote {
  my $class = shift;
  my $branch = $class->_get_current_branch();
  my $remote = `git config --get branch.$branch.remote`;
  chomp($remote);

  if (length($remote)) {
    return $remote;
  }
  return $class->_get_remotes();
}

sub _get_remotes {
  my @remotes = `git remote`;
  chomp(@remotes);
  my $remote = $remotes[0];

  if (scalar @remotes > 1) {
    $remote = Daemon::prompt("Please choose a remote", $remote, [@remotes]);
  }
  return $remote;
}

sub _get_origin_url {
  my $class = shift;
  my $remote = $class->_get_remote();
  my $origin = `git config --get remote.$remote.url`;
  chomp($origin);
  return $origin;
}

sub _get_tracked_branch {
  my $class = shift;
  my $branch = $class->_get_current_branch();
  my $tracked_branch = `git rev-parse --abbrev-ref $branch\@{upstream} 2>/dev/null`;
  chomp($tracked_branch);
  return $tracked_branch;
}

sub _get_project_name {
  my $class = shift;
  my $p_root = $class->root() or die "Cannot find git project root";
  my @content = Daemon::read($p_root . "/.git/description");
  my $p_name = "@content";
  chomp($p_name);

  return ($p_name ne "Unnamed repository; edit this file 'description' to name the repository.") ? $p_name : undef;
}

sub _get_issue {
  my $class = shift;
  my $branch = $class->_get_current_branch();
  my $config = $class->_get_config();
  my $issue;

  if ($config->{issue_tracker}) {
    my $issue_tracker = $config->{issue_tracker};
    my $it_storage = $class->{$issue_tracker}->_get_storage();
    if ($it_storage->{issues}->{$branch}->{issue_id}) {
      $issue = $class->{$issue_tracker}->_get_issue($it_storage->{issues}->{$branch}->{issue_id});
    }
  }

  return $issue;
}

sub _get_issue_trackers {
  return Memento::IssueTracker->_get_all();
}

sub _get_time_trackers {
  return Memento::TimeTracker->_get_all();
}

sub _is_configured {
  my @config = trim `git config -l | grep memento`;
  return scalar @config > 1 ? 1 : 0;
}

sub _get_modified_files {
  my $class = shift;
  my $files = `git ls-files --other --modified --exclude-standard`;
  chomp($files);
  return $files;
}

sub _get_source {
  my $class = shift;
  my $config = $class->_get_config();
  my $source = shift || $config->{branch}->{source};
  my $branch = $class->_get_current_branch();
  my $storage = $class->_get_storage();
  my $source_branch = Daemon::printColor($source, "black on_bright_yellow");

  if (!$storage->{$branch}->{source}) {
    say "No source branch has been configured for $branch";
    if (Daemon::prompt("Do you want to configure $source_branch as source branch for $branch?", 'yes', ['yes', 'no']) eq 'no') {
      die "Aborting...\n";
    }
    $class->_set_source($source);
  }
  else {
    $source = $storage->{$branch}->{source};
  }

  return $source;
}

sub _set_source {
  my $class = shift;
  my $source = shift || 0;
  my $storage = $class->_get_storage();
  my $branch = $class->_get_current_branch();

  if (!$source) {
    die "Missing source argument parameter.\n";
  }

  say "Updating your branch configurations...";
  my $source_branch = Daemon::printColor($source, "black on_bright_yellow");
  $storage->{$branch}->{source} = $source;
  $class->_save_storage($storage);
  say "Branch $source_branch has been configured as source branch for $branch";
}

1;
