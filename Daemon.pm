#!/Applications/MAMP/Library/bin/perl
use feature 'say';
package Daemon;
use Cwd;
use JSON::PP;
use Text::Aligner;
use Text::Table;

sub write {
  if (($#_ + 1) != 4) {
    die("Missing arguments for write()");
  }

  $file = $_[0];		# File name.
  $content = $_[1]; # Content to be written into the file.
  $create = $_[2];	# 1 or 0: Whether or not create the file.
  $method = $_[3];	# > or >> to overwrite or append $content.

  if (!-f $file) {
    if ($create == 1) {
      $method = '>';
      # say "Creating file $file";
    }
    else {
      die("File $file does not exists");
    }
  }
  else {
    # say "Updating file $file";
  }

  open(my $fh, $method, $file);
  say $fh $content;
  close $fh;
}

sub read {
  if (($#_ + 1) != 1) {
    die("Missing arguments for read()");
  }

  $file = $_[0];		  # Name the file
  open(INFO, $file);	# Open the file
  @lines = <INFO>;		# Read it into an array
  close(INFO);			  # Close the file
  return @lines;			# Print the array
}

sub json_decode_file {
  my $file = shift;
  my $data = undef;
  if ((-s $file) && (open (my $json_stream, $file))) {
    local $/ = undef;
    my $json = JSON::PP->new->utf8;
    $data = $json->decode(<$json_stream>);
    close($json_stream);
  }
  return $data;
}

sub open_default_browser {
  my $url = shift;
  my $platform = $^O;
  my $cmd;
  if    ($platform eq 'darwin')  { $cmd = "open \"$url\"";          } # Mac OS X
  elsif ($platform eq 'linux')   { $cmd = "x-www-browser \"$url\""; } # Linux
  elsif ($platform eq 'MSWin32') { $cmd = "start $url";             } # Win95..Win7
  if (defined $cmd) {
    system($cmd);
  } else {
    die "Can't locate default browser";
  }
}

sub promptUser {
   my ($promptString, $defaultValue) = @_;

   if ($defaultValue) {
      print $promptString, "[", $defaultValue, "]: ";
   } else {
      print $promptString, ": ";
   }

   $| = 1;               # force a flush after our print
   $_ = <STDIN>;         # get the input from STDIN (presumably the keyboard)

   chomp;

   if ("$defaultValue") {
      return $_ ? $_ : $defaultValue;    # return $_ if it has a value
   } else {
      return $_;
   }
}

sub json2table {
  my $title = shift;
  my $items = shift || ();
  my @exclude = shift || [];
  my @header = ();
  my @rows = ();
  my $i = 0;

  for my $item (@{$items}) {
    if ($i == 0) {
      for my $key (sort keys %{$item}) {
        # @todo rework, including string values of HASH items.
        if (ref($item->{$key}) ne 'HASH' && !in_array(@exclude, $key)) {
          push(@header, uc $key);
        }
      }
    }
    $i = 1;

    my @row = ();
    for my $key (@header) {
      push(@row, $item->{lc $key});
    }
    push(@rows, [@row]);
  }

  my $table = Text::Table->new(@header);
  $table->load(@rows);

  use Term::ANSIColor;
  &printLabel($title);
  say colored(['black on_white'], $table);
}

sub printLabel {
  my $label = shift;
  my $color = shift || "white on_black";
  my $padding = " " x ((length $label) + 2);

  use Term::ANSIColor;
  say colored([$color], "$padding\n $label \n$padding");
}

sub in_array {
  my ($arr,$search_for) = @_;
  my %items = map {$_ => 1} @$arr;
  return (exists($items{$search_for}))?1:0;
}

sub storage {
  chdir;
  my $home = cwd;
  my $storage = "$home/.memento";

  if (!-d $storage) {
    mkdir($storage) or die "Cannot create .memento dir in your home directory: $!\n";
  }

  return $storage;
}

1;