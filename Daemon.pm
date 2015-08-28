#!/usr/bin/env perl
package Daemon;

use feature 'say';
use Cwd;
use JSON::PP;
use Term::ANSIColor;
use Term::Complete;
use Text::Aligner;
use Text::ASCIITable;
use Text::Table;
use Hash::Merge qw( merge );
use HTTP::Response;
use WWW::Curl::Easy;
use Data::Dumper;

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
    }
    else {
      die("File $file does not exists");
    }
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
    my $json = JSON::PP->new->allow_nonref;
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

sub prompt {
  my $question = shift;
  my $defaultValue = shift;
  my @options = shift;
  my $answer = undef;
  my $printed_list = 0;

  do {
    if ($defaultValue) {
      print $question, "[", $defaultValue, "]: ";
    }
    else {
      print $question, ": ";
    }

    if (@options[0] && !$printed_list) {
      print "\n";
      print_list(@options);
      $printed_list = 1;
      print "» ";
    }
    $| = 1;        # force a flush after our print

    if (@options[0]) {
      $_ = Complete('', @options);
    }
    else {
      $_ = <STDIN>;  # get the input from STDIN
      chomp;
    }

    if ("$defaultValue") {
      $answer = $_ ? $_ : $defaultValue;    # return $_ if it has a value
    }
    else {
      $answer = $_;
    }
  }
  while (!$answer || !length $answer || (@options[0] && !in_array(@options, $answer)));

  if ($printed_list) {
    print "\n";
  }

  return $answer;
}

sub array2table {
  my $title = shift;
  my $items = shift || ();
  my $options = shift;
  my $default = {
    exclude => [],
    allow_nested => 1,
    extract_nested_key => 'name',
  };
  $options = merge($default, $options);

  my @header = ();
  my @rows = ();
  my $i = 0;

  for my $item (@{$items}) {
    if ($i == 0) {
      for my $key (sort keys %{$item}) {
        if (!in_array($options->{exclude}, $key)) {
          my $ref = ref($item->{$key});
          if (($ref ne 'HASH') || $options->{allow_nested}) {
            push(@header, uc $key);
          }
        }
      }
    }
    $i = 1;

    my @row = ();
    for my $key (@header) {
      my $ref = ref($item->{lc $key});
      my $value;

      if (($ref eq 'HASH')) {
        if ($options->{allow_nested}) {
          if ($options->{full_nested}) {
            $value = array2table(0, [$item->{lc $key}]);
          }
          else {
            $value = $item->{lc $key}->{$options->{extract_nested_key}};
          }
        }
      }
      else {
        $value = $item->{lc $key};
      }

      push(@row, $value);
    }
    push(@rows, [@row]);
  }

  if (@rows) {
    if ($options->{colored}) {
      my $table = Text::Table->new(@header);
      $table->load(@rows);
      &printLabel($title);
      return colored(['black on_bright_white'], $table);
    }
    else {
      my $args = $title ? { headingText => $title } : {};
      $t = Text::ASCIITable->new($args);
      $t->setCols(@header);
      for my $row (@rows) {
        $t->addRow($row);
      }
      return $t;
    }
  }
}

sub printLabel {
  my $label = shift;
  my $color = shift || "bold white on_rgb015";
  say colored([$color], uc " $label ");
}

sub in_array {
  my ($arr, $search_for) = @_;
  my %items = map {$_ => 1} @$arr;
  return (exists($items{$search_for})) ? 1 : 0;
}

sub print_list {
  my $array = shift;
  foreach my $item (@{$array}) {
    say "- $item";
  }
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

sub http_request {
  my $uri = shift;
  my @header = shift;
  my %options = shift;
  my $curl = WWW::Curl::Easy->new;

  $curl->setopt(CURLOPT_HEADER,1);
  $curl->setopt(CURLOPT_URL, $uri);
  $curl->setopt(CURLOPT_HTTPHEADER, @header);
  $curl->setopt(CURLOPT_SSL_VERIFYPEER, 0);
  $curl->setopt(CURLOPT_TIMEOUT, 3);

  if (%options) {
    for my $key (keys %options) {
      $curl->setopt($key, $options{$key});
    }
  }

  my $response;
  $curl->setopt(WWW::Curl::Easy::CURLOPT_WRITEDATA, \$response);

  my $retcode = $curl->perform;
  my $content;
  if ($retcode == 0) {
    $response = HTTP::Response->parse($response);
    $content = $response->decoded_content;
  }
  else {
    die sprintf('HTTP request error %d (%s): %s', $retcode, $curl->strerror($retcode), $curl->errbuf);
  }

  return $content;
}

1;
