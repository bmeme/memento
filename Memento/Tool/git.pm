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
      my $p_name = Daemon::prompt("Set/confirm current project name", $default->{project});

      say "";
      Daemon::printLabel("Branch configurations");
      my @branches = $class->_get_branches();
      my $source = Daemon::prompt('Specify source branch for "memento git start"', $default->{branch}->{source}, [@branches]);
      my $destination = Daemon::prompt('Specify destination branch for "memento git finish"', $default->{branch}->{destination}, [@branches]);
      my $delete = Daemon::prompt('Do you want to automatically delete the new branch after "memento git finish"?', 'no', ['no', 'local', 'remote + local']);
      $delete = ($delete eq 'no') ? 0 : (($delete eq 'local') ? 1 : 2);

      my $issue_tracker = 0;
      if (Daemon::prompt('Do you want to enable Issue Tracker support?', 'yes', ['yes', 'no']) eq 'yes') {
        $issue_tracker = Daemon::prompt('Choose an Issue Tracker', $default->{issue_tracker}, $class->_get_issue_trackers());
      }
      my $pattern = $issue_tracker ? Daemon::prompt('Please specify your branch naming convention (you can use issue properties as tokens)', $default->{branch}->{pattern}) : 0;

      say "";
      my $time_tracker = 0;
      if (Daemon::prompt('Do you want to enable Time Tracker support?', 'yes', ['yes', 'no']) eq 'yes') {
        $time_tracker = Daemon::prompt('Choose a Time Tracker', $default->{time_tracker}, $class->_get_time_trackers());
      }

      say "";
      Daemon::printLabel("Git Hooks");
      my $commit_validation = 0;
      if (Daemon::prompt("Do you want to set a validation for your commit messages?", 'no', ['yes', 'no']) eq 'yes') {
        $commit_validation = Daemon::prompt('Enter regex to be used as commit validation (without leading and trailing slashes)', $default->{hooks}->{commit_msg});
        $commit_validation =~ s/\\/\\\\/g;
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
        time_tracker => $time_tracker
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
  system("git log --pretty=format:\"%h %ad | %s%d [%an]\" --graph --date=short");
}

sub root {
  my $class = shift;
  my $goto = shift || 0;
  my $p_root = `git rev-parse --show-toplevel`;
  chomp($p_root);

  if ($goto) {
    chdir $p_root;
  }
  else {
    return $p_root;
  }
}

sub start {
  my $class = shift;
  my $config = $class->_get_config();
  my $branch;
  my @branches = $class->_get_branches();
  my $source = $config->{branch}->{source};
  chomp($source);

  GetOptions(
    'source=s' => \$source
  ) or die 'Incorrect usage';

  if (!Daemon::in_array([@branches], $source)) {
    die "You have specified an invalid source branch: $source\n";
  }

  my $issue;

  if ($config->{issue_tracker}) {
    my $issue_tracker = $config->{issue_tracker};
    my $id = Daemon::prompt("Enter $issue_tracker issue id");
    $issue = $class->{$issue_tracker}->_get_issue($id);
    if (!$issue) {
      die "You have specified an invalid issue id.";
    }

    say "You are going to create a new branch for the following issue:\n";
    $class->{$issue_tracker}->_render_issue($issue);
    if (Daemon::prompt("Do you confirm?", 'yes', ['yes', 'no']) eq 'no') {
      die "Aborting...\n";
    }

    $branch = trim $config->{branch}->{pattern};
    $branch =~ s/:(\w+):/$issue->{$1}/g;
    $branch =~ s/:(\w+)-(\w+):/$issue->{$1}->{$2}/;
    $branch = "$branch";
  }
  else {
    $branch = Daemon::prompt("Enter the branch name");
  }

  $branch = $class->_check_branch_name($branch);
  my $current_branch = $class->_get_current_branch();

  if (($branch eq $current_branch) && (Daemon::prompt("New branch and current branch are the same. Continue anyway?", 'no', ['yes', 'no']) eq 'no')) {
    die "Now exiting.\n";
  }

  if (Daemon::in_array([@branches], $branch)) {
    # Checkout to existing branch.
    system("git checkout $branch");
  }
  else {
    # Create a new branch from the specified source.
    system("git checkout -b $branch $source");

    # Set upstream for the new branch if a remote origin exists.
    if ($class->_get_origin_url() && !$class->_get_tracked_branch()) {
      `git push --set-upstream origin $branch`;
      say "Configured upstream for branch '$branch'";
    }
  }
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
  my $remote = $class->_get_remote();

  my $safe = 0;
  GetOptions(
    'safe!' => \$safe
  ) or die 'Incorrect usage';

  if ($safe) {
    my @branches = $class->_get_branches();
    my $delete_modes = ['no', 'local', 'remote + local'];
    my $delete_default = $delete ? @{$delete_modes}[$delete] : 'no';

    $destination = Daemon::prompt('Specify destination branch for merge', $destination, [@branches]);
    $delete = Daemon::prompt("Do you want to delete branch '$branch' after merge?", $delete_default, ['no', 'local', 'remote+local']);
    $delete = ($delete eq 'no') ? 0 : (($delete eq 'local') ? 1 : 2);
  }

  my $issue = $class->_get_issue();
  if ($destination && ($destination ne $branch)) {
    system("git push $remote $branch") if ($remote);
    system("git checkout $destination");
    system("git pull $remote $destination") if ($remote);
    system("git merge $branch");
    system("git push $remote $destination") if ($remote);
    system("git branch -D $branch") if ($delete);
    system("git push $remote :$branch") if ($remote && ($delete == 2));
  }
  else {
    die "Current branch and destination branch are the same. Cannot proceed.\n";
  }

  $class->_on('git_flow_finish', {branch => $branch, issue => $issue});
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
  my $source = $class->_get_current_branch();

  return {
    project => undef,
    branch => {
      source => $source,
      destination => $source,
      delete => 0,
      pattern => 'feature/:id:-:subject:'
    },
    hooks => {
      commit_msg => 0,
      pre_commit => 0,
      post_commit => 0
    },
    issue_tracker => 0,
    time_tracker => 0
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
    my $time_tracker = `git config memento.time-tracker`;

    chomp($source);
    chomp($destination);
    chomp($delete);
    chomp($pattern);
    chomp($commit_msg);
    chomp($pre_commit);
    chomp($post_commit);
    chomp($issue_tracker);
    chomp($time_tracker);

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
      time_tracker => $time_tracker
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

sub _save_config {
  my $class = shift;
  my $config = shift;

  $class->root(1);
  Daemon::write('.git/description', $config->{project}, 1, '>');

  system("git config memento.branch.source " . $config->{branch}->{source});
  system("git config memento.branch.destination " . $config->{branch}->{destination});
  system("git config memento.branch.delete " . $config->{branch}->{delete});
  system("git config memento.branch.pattern " . $config->{branch}->{pattern});
  system("git config memento.hooks.commit-msg " . $config->{hooks}->{commit_msg});
  system("git config memento.hooks.pre-commit " . $config->{hooks}->{pre_commit});
  system("git config memento.hooks.post-commit " . $config->{hooks}->{post_commit});
  system("git config memento.issue-tracker " . $config->{issue_tracker});
  system("git config memento.time-tracker " . $config->{time_tracker});

  # Enable Git Hooks.
  my $git_hooks = Memento::Tool->root() . "/misc/git-hooks.pl";
  my $git_hooks_dir = getcwd() . "/.git/hooks";

  system("ln -s $git_hooks $git_hooks_dir/commit-msg")  if (!-f "$git_hooks_dir/commit-msg");
  system("ln -s $git_hooks $git_hooks_dir/pre-commit") if (!-f "$git_hooks_dir/pre-commit");
  system("ln -s $git_hooks $git_hooks_dir/post-commit") if (!-f "$git_hooks_dir/post-commit");

  $class->SUPER::_save_config($config);
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
  if (-d '.git') {
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
        system($git_command);
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

  $branch =~ /^(feature|\w+)\//;
  my $prefix = $1 ? $1 : "feature";

  $branch =~ s/^$prefix\///g;
  $branch = Daemon::machine_name($branch);
  $branch = "$prefix/$branch";
  return $branch;
}

sub _delete_config {
  my $class = shift;
  my $p_root = $class->root() or die "Cannot find git project root";
  my $git_hooks = Memento::Tool->root() . "/misc/git-hooks.pl";

  # Delete memento git configurations if exist.
  if (&_is_configured()) {
    system("git config --remove-section memento.branch");
    system("git config --remove-section memento.hooks");
    system("git config --remove-section memento");
  }

  # Delete git hooks symlinks if exist.
  my $git_hooks_dir = "$p_root/.git/hooks";
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
  my $branch_list = trim `git branch`;
  $branch_list =~ s/\* //;
  return split(' ', $branch_list);
}

sub _get_current_branch {
  my $branch = `git rev-parse --abbrev-ref HEAD`;
  chomp($branch);
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
  return $remote;
}

sub _get_origin_url {
  my $origin = `git config --get remote.origin.url`;
  chomp($origin);
  return $origin;
}

sub _get_tracked_branch {
  my $class = shift;
  my $branch = $class->_get_current_branch();
  my $tracked_branch = `git rev-parse --abbrev-ref $branch\@{upstream}`;
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

1;