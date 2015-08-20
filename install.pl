#!/usr/bin/env perl
use strict; use warnings;
use feature 'say';
use Cwd;

our $cwd = getcwd();
my $cpan_path = `which cpan`;

if (!$cpan_path) {
  say "Please install cpan command line tool in order to proceed with the installation.";
  say "http://www.cpan.org/modules/INSTALL.html\n";
  die "Installation aborted.\n";
}

my @vendors = (
  'Class::MOP',
  'Hash::Merge',
  'Switch',
  'Term::ProgressBar',
  'Text::Aligner',
  'Text::ASCIITable',
  'Text::Table',
  'Text::Trim',
  'WWW::Curl'
);

say "Installing vendors:";
foreach my $vendor (@vendors) {
  print "[$vendor] installing...\r";
  `cpan -i $vendor`;
  print "[$vendor] ...installed!\n";
}

chdir;
my $home = cwd;
my $storage = "$home/.memento";
if (!-d $storage) {
  mkdir($storage) or die "Cannot create .memento dir in your home directory: $!\n";
}

if (!-f "/usr/local/bin/memento") {
  `ln -s $cwd/memento.pl /usr/local/bin/memento`;
}

say "Memento installation finished.";
