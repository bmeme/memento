#!/usr/bin/env perl
package Daemon;

use feature 'say';
use Cwd;
use File::HomeDir;
use JSON::PP;
use Switch;
use Term::ANSIColor;
use Term::Complete;
use Text::Aligner;
use Text::ASCIITable;
use Text::Table;
use Hash::Merge qw( merge );
use HTTP::Response;
use URI;
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

sub open_default_editor {
  my $filename = shift or die "Missing filename to open\n";
  if (!-f $filename) {
    die "Cannot find $filename! $!\n";
  }
  my $editor = $ENV{EDITOR} || 'vim';
  system $editor => $filename;
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
  my $header_row = 1;

  for my $item (@{$items}) {
    if ($header_row) {
      for my $key (sort keys %{$item}) {
        if (!in_array($options->{exclude}, $key)) {
          my $ref = ref($item->{$key});
          if (($ref ne 'ARRAY') || ($ref ne 'HASH') || $options->{allow_nested}) {
            push(@header, uc $key);
          }
        }
      }
    }
    $header_row = 0;

    my @row = ();
    for my $key (@header) {
      my $ref = ref($item->{lc $key});
      my $value;

      if ((($ref eq 'HASH') || ($ref eq 'ARRAY')) && $options->{allow_nested}) {
        if ($ref eq 'HASH') {
          if ($options->{full_nested}) {
            $value = array2table(0, [$item->{lc $key}], $options);
          }
          else {
            $value = $item->{lc $key}->{$options->{extract_nested_key}};
          }
        }
        else {
          $value = array2table(0, $item->{lc $key}, $options);
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

  return '';
}

sub printLabel {
  my $label = shift;
  my $color = shift || "bold white on_rgb015";
  my $no_upper = shift || 0;
  $label = $no_upper ? " $label " : uc " $label ";
  say colored([$color], $label);
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
  my $home = File::HomeDir->my_home;
  my $storage = "$home/.memento";

  if (!-d $storage) {
    mkdir($storage) or die "Cannot create .memento dir in your home directory: $!\n";
  }

  return $storage;
}

sub http_request {
  my $method = shift || 'GET';
  my $uri = shift;
  my $data = shift || {};
  my @header = shift;
  my %options = shift;
  my $curl = WWW::Curl::Easy->new;

  $method = uc $method;
  if (!in_array(['GET', 'POST', 'PUT', 'DELETE'], $method)) {
    die "Invalid HTTP Method supplied: $method\n";
  }

  $uri = URI->new($uri);
  $curl->setopt(CURLOPT_CUSTOMREQUEST, $method);

  switch ($method) {
    case 'GET' {
      my %querystring = %{$data};
      $uri->query_form(%querystring);
    }
    case 'PUT' {
      $curl->setopt(CURLOPT_POSTFIELDS, encode_json $data);
    }
    case 'POST' {
      $curl->setopt(CURLOPT_POSTFIELDS, encode_json $data);
    }
    case 'DELETE' {

    }
  }

  $curl->setopt(CURLOPT_HEADER,1);
  $curl->setopt(CURLOPT_URL, $uri);
  $curl->setopt(CURLOPT_HTTPHEADER, @header);
  $curl->setopt(CURLOPT_SSL_VERIFYPEER, 0);
  $curl->setopt(CURLOPT_TIMEOUT, 5);

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

sub machine_name {
  my $name = shift;

  $name = lc $name;
  $name =~ s/[^\w\/\#\-]+/_/g; #converts anything different from the pattern.
  $name =~ s/_+\-+_*/_/g;      #removes "_-_".
  $name =~ s/^\w{1,2}_|_\w{1,2}_|_\w{1,2}$/_/g; #removes short words (<= 2).
  $name =~ s/^_|_$//g;         #removes trailing and leading "_".

  return $name;
}

1;
