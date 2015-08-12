#!/usr/bin/perl
use feature 'say';
package Daemon;

sub root {
  $root = `git rev-parse --show-toplevel`;
  chop($root);
  chdir $root;
}

sub write {
  if (($#_ + 1) != 4) {
    die("Missing arguments for file_put_contents()");
  }

  $file = $_[0];		# File name.
  $content = $_[1]; # Content to be written into the file.
  $create = $_[2];	# 1 or 0: Whether or not create the file.
  $method = $_[3];	# > or >> to overwrite or append $content.

  if (!-f $file) {
    if ($create == 1) {
      $method = '>';
      say "Creating file $file";
    }
    else {
      die ("File $file does not exists");
    }
  }
  else {
    say "Updating file $file";
  }

  open(my $fh, $method, $file);
  say $fh $content;
  close $fh;
}

sub read {
  if (($#_ + 1) != 1) {
    die("Missing arguments for file_get_contents()");
  }

  $file = $_[0];		  # Name the file
  open(INFO, $file);	# Open the file
  @lines = <INFO>;		# Read it into an array
  close(INFO);			  # Close the file
  say @lines;			    # Print the array
}
1;