#!/usr/bin/env perl
use strict; use warnings;
use feature 'say';
use Cwd;
use Data::Dumper;

our $cwd = getcwd();
my $cpan_path = `which cpan`;

if (!$cpan_path) {
  say "Please install cpan command line tool in order to proceed with the installation.";
  say "http://www.cpan.org/modules/INSTALL.html\n";
  die "Installation aborted.\n";
}

say "Installing vendors:";
my @vendors = (
  'Class::MOP',
  'Hash::Merge',
  'Switch',
  'FLORA/Term-Complete-1.402.tar.gz',
  'Term::ProgressBar',
  'Text::Aligner',
  'Text::ASCIITable',
  'Text::Table',
  'Text::Trim',
  'WWW::Curl'
);

foreach my $vendor (@vendors) {
  print "[-] $vendor";
  `cpan -i $vendor`;
  print "\r[√] $vendor\n";
}

say "\nApplying patches:";
foreach my $vendor (@vendors) {
  $vendor =~ s/^[A-Z]+\/(\w+)\-(\w+)(.*)/$1::$2/;
  my $patches_dir = "$cwd/Patches/$vendor";
  if (-d $patches_dir) {
    say "[$vendor]";
    my @list;

    opendir(DIR, $patches_dir) || die "Can't open directory $patches_dir: $!";
    @list = grep /\.patch$/, readdir(DIR);
    closedir DIR;

    my $file = $vendor;
    $file =~ s/(\w+)\:\:(\w+)/$1\/$2.pm/i;
    foreach my $path (@INC) {
      my $full_path = "$path/$file";
      if (-f $full_path) {
        foreach my $patch (@list) {
          say "Applying patch $patch at $full_path...";
          system("patch -s -N $full_path $patches_dir/$patch");
        }
      }
    }
  }
}

chdir;
my $home = cwd;
my $storage = "$home/.memento";
if (!-d $storage) {
  say "\nCreating ~/.memento folder";
  mkdir($storage) or die "Cannot create .memento dir in your home directory: $!\n";
}

if (!-f "/usr/local/bin/memento") {
  say "\nCreating memento symlink";
  `ln -s $cwd/memento.pl /usr/local/bin/memento`;
}

say "\nMemento installation finished.";
