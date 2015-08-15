#!/Applications/MAMP/Library/bin/perl
use strict; use warnings;
use feature 'say';
use Cwd;

our $cwd = cwd;
my $cpan_path = `which cpan`;

if (!$cpan_path) {
  say "Please install cpan command line tool in order to proceed with the installation.";
  say "http://www.cpan.org/modules/INSTALL.html\n";
  die "Installation aborted.\n";
}

my @vendors = (
  'Class::MOP',
  'Text::Aligner',
  'Text::Table',
  'Text::Trim'
);

foreach my $vendor (@vendors) {
  print "[$vendor] installing vendor...\n";
  say `cpan -i -f $vendor`;
  say "Reading module description...";
  say `cpan -D $vendor`;
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

say "Memento installation finished";
