#!/usr/bin/perl
#
# Program to do the obvious
#
use feature 'say';
use Cwd;
use JSON::PP;
use Data::Dumper;

my $memento = {}; bless $memento, "Memento";
$command = shift(@ARGV);
$memento->$command(@ARGV);

sub Memento::redmine {
  my $key = $ENV{'MMNT_RM_KEY'};
  my $redmine_url = $ENV{'MMNT_RM_URL'};
  my $filename = 'response.json';
  `curl -k -H "Content-Type: application/json" -X GET -H "X-Redmine-API-Key: $key" $redmine_url/issues.json 2>&1> $filename`;
  my $data;
  if (open (my $json_stream, $filename))
  {
        local $/ = undef;
        my $json = JSON::PP->new;
        $data = $json->decode(<$json_stream>);
        close($json_stream);
  }
  print $data->{'total_count'};
}

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