#!/usr/bin/perl
#
# Program to do the obvious
#
use feature 'say';
use Cwd;

$command = shift(@ARGV);
my $obj = bless [] => 'Memento';
$obj->$command(@ARGV);

sub Memento::status {
  say `git status -s`;
}

sub Memento::add {
  Daemon::root();
  `git add .`;
  Memento::status();
}

sub Memento::remove {
  $file = $_[1];
  if (!-e $file) {
    die("Trying to remove not existing file: $file");
  }
  Daemon::root();
  `git reset $file`;
  Memento::status();
}

sub Memento::ignore {
  $ignore = $_[1];
  Daemon::root();
  Daemon::write(".gitignore", $ignore, 1, '>>');
  say "$ignore added to .gitignore";
}

sub Daemon::root {
  $root = `git rev-parse --show-toplevel`;
  chop($root);
  chdir $root;
}

sub Daemon::write {
  if (($#_ + 1) != 4) {
    die("Missing arguments for file_put_contents()");
  }

  $file = $_[0];		# File name.
  $content = $_[1]; # Content to be written into the file.
  $create = $_[2];	# 1 or 0: Whether or not create the file.
  $method = $_[3];	# > or >> to overwrite or append $content.
  say $file;

  if (!-f $file) {
    if ($create == 1) {
      $method = '>';
      say "Creating file $file";
    }
    else {
      die ("File $file does not exists");
    }
  }

  open(my $fh, $method, $file);
  say $fh $content;
  close $fh;
}

sub Daemon::read {
  if (($#_ + 1) != 1) {
    die("Missing arguments for file_get_contents()");
  }

  $file = $_[0];		  # Name the file
  open(INFO, $file);	# Open the file
  @lines = <INFO>;		# Read it into an array
  close(INFO);			  # Close the file
  say @lines;			    # Print the array
}