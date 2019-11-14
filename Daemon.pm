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
use Text::Trim;
use Text::Unidecode;
use Hash::Merge qw( merge );
use HTTP::Response;
use URI;
use LWP::UserAgent;
use Env;

our($progress_index) = 1;
our($progress_step) = 1;

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
  my $max_length = shift;
  my $answer = undef;
  my $printed_list = 0;
  my $hash = 0;
  my $remaining = 0;
  my $has_options = 0;

  if (ref(@options[0]) eq 'HASH') {
    $hash = @options[0];
    @options = [sort keys %{$hash}];
  }

  if (ref(@options[0]) eq 'ARRAY') {
    $has_options = 1;
  }

  do {
    if ($defaultValue) {
      print $question, "[", $defaultValue, "]: ";
    }
    else {
      print $question, ": ";
    }

    if (!$has_options && $max_length) {
      print "[max-length: $max_length]: ";
      $remaining = $max_length;
    }
    else {
      $remaining = 0;
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

    if (!$has_options && $max_length) {
      $remaining = $max_length - length $answer;
      if ($remaining < 0) {
        Daemon::printLabel("Max length exceeded: $remaining", "black on_red", 1);
      }
    }
  }
  while (!$answer || !length $answer || ($remaining < 0) || ($has_options && !in_array(@options, $answer)));

  if ($printed_list) {
    print "\n";
  }

  if ($hash) {
    $answer = $hash->{$answer};
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
  my @header_keys = ();
  my @rows = ();
  my $header_row = 1;

  for my $item (@{$items}) {
    if ($header_row) {
      for my $key (sort keys %{$item}) {
        if (!in_array($options->{exclude}, $key)) {
          my $ref = ref($item->{$key});
          if (($ref ne 'ARRAY') || ($ref ne 'HASH') || $options->{allow_nested}) {
            push(@header, uc $key);
            push(@header_keys, $key);
          }
        }
      }
    }
    $header_row = 0;

    my @row = ();
    for my $key (@header_keys) {
      my $ref = ref($item->{$key});
      my $value;

      if ((($ref eq 'HASH') || ($ref eq 'ARRAY')) && $options->{allow_nested}) {
        if ($ref eq 'HASH') {
          if ($options->{full_nested}) {
            $value = array2table(0, [$item->{$key}], $options);
          }
          else {
            $value = $item->{$key}->{$options->{extract_nested_key}};
          }
        }
        else {
          $value = array2table(0, $item->{$key}, $options);
        }
      }
      else {
        $value = $item->{$key};
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

sub system {
  my $command = shift;
  my $retMessage = printColor($command, "white on_red");

  say "▶ $command";
  0 == system($command)
      or die "There was an error while trying to execute command $retMessage. Fix the problem and try again\n";
}

sub printLabel {
  my $label = shift;
  my $color = shift || "bold white on_rgb015";
  my $lower = shift;
  $label = $lower ? $label : uc $label;
  say colored([$color], " $label ");
}

sub printColor {
  my $label = shift;
  my $color = shift || "bold white on_rgb015";
  my $upper = shift;
  $label = $upper ? uc $label : $label;
  return colored([$color], " $label ");
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
  my $headers = shift || {};
  my $credentials = shift;
  my $client = LWP::UserAgent->new;
  my $content = undef;
  my $timeout = $ENV{MEMENTO_HTTP_TIMEOUT} ? $ENV{MEMENTO_HTTP_TIMEOUT} : 10;

  $client->timeout($timeout);
  $ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;
  $client->ssl_opts( verify_hostname => 0, SSL_verify_mode => 0x00);

  $method = uc $method;
  if (!in_array(['GET', 'POST', 'PUT', 'DELETE', 'PATCH'], $method)) {
    die "Invalid HTTP Method supplied: $method\n";
  }

  $uri = URI->new($uri);
  if ($method eq 'GET') {
    my %querystring = %{$data};
    $uri->query_form(%querystring);
    $data = undef;
  }

  my $req = HTTP::Request->new($method => $uri);

  # Set request credentials.
  if ($credentials) {
    $req->authorization_basic($credentials->{user}, $credentials->{pass});
  }

  # Set request headers.
  foreach my $key (keys %$headers) {
    $req->header($key => $headers->{$key});
  }

  if ($data) {
    $req->content(encode_json $data);
  }

  my $resp = $client->request($req);

  if ($resp->is_success) {
    $content = $resp->decoded_content;
  }
  else {
    say "HTTP $method error code: ", $resp->code;
    say "HTTP $method error message: ", $resp->message;
    die("\n");
  }

  return $content;
}

sub machine_name {
  my $name = shift;

  $name = lc unidecode($name);
  $name =~ s/(\w)\-([a-z])/$1_$2/g; #converts dashes between a char and a number.
  $name =~ s/[^\w\-]+/_/g; #converts anything different from the pattern.
  $name =~ s/^_\w{1,2}|_\w{1,2}_|_\w{1,2}$/_/g; #removes short words (<= 2).
  $name =~ s/_{2,}/_/g;  #removes multiple underscores.
  $name =~ s/^_|_$//g;   #removes trailing and leading "_".
  $name =~ s/_[\w\-]_/_/g;  #converts dirty segments to "_".
  $name =~ s/_\-_/_/g; #converts "_-_" to "_".
  $name =~ s/^_\w{1,2}|_\w{1,2}_|_\w{1,2}$/_/g; #recheck for short words (<= 2).
  return $name;
}

sub current_dir_name {
  my @dir = split('/', getcwd());
  return $dir[-1];
}

1;
