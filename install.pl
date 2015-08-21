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

my @vendors = (
  'Class::MOP',
  'Hash::Merge',
  'Switch',
  'Term::Complete',
  'Term::ProgressBar',
  'Text::Aligner',
  'Text::ASCIITable',
  'Text::Table',
  'Text::Trim',
  'WWW::Curl'
);

say "Installing vendors:";
foreach my $vendor (@vendors) {
  #@TODO this could be done better... T_T
  my $span = (length $vendor > 13) ? "\t" : "\t\t";
  print "[$vendor]" . $span . "[-]\r";
  #`cpan -i $vendor`;
  print "[$vendor]" . $span . "[√]\n";
}

say "\nApplying patches:";
foreach my $vendor (@vendors) {
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
          print "Applying patch $patch for $full_path ... ";
          chdir $full_path;
          system("patch -p1 < $patches_dir/$patch");
          say "patched!";
        }
      }
    }
  }
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
