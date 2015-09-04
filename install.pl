#!/usr/bin/env perl
use strict; use warnings;
use feature 'say';
use Cwd;
use File::HomeDir;
use Data::Dumper;

our $cwd = getcwd();
my $cpan_path = `which cpan`;

if (!$cpan_path) {
  say "Please install cpan command line tool in order to proceed with the installation.";
  say "http://www.cpan.org/modules/INSTALL.html\n";
  die "Installation aborted.\n";
}

say ">> Installing vendors:";
my @vendors = (
  'Class::MOP',
  'Class::Observable',
  'DateTime',
  'DateTime::Format::Strptime',
  'File::HomeDir',
  'Git::Hooks',
  'Hash::Merge',
  'HTTP::Response',
  'Switch',
  'FLORA/Term-Complete-1.402.tar.gz',
  'Term::ANSIColor',
  'Term::ProgressBar',
  'Text::Aligner',
  'Text::ASCIITable',
  'Text::Table',
  'Text::Trim',
  'WWW::Curl'
);

foreach my $vendor (@vendors) {
  say "\n>> Installing [$vendor]";
  system("cpan -i $vendor");
}

say "\n>> Applying patches:";
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
          system("patch -sN $full_path $patches_dir/$patch");
        }
      }
    }
  }
}

print "\n>> Generating Memento man page: ";
my $man_dir = $cpan_path;
chomp($man_dir);
$man_dir =~ s/\/bin\/cpan$//;
my $man = `pod2man -s 1 -c Memento memento.pl > $man_dir/share/man/man7/memento.7`;
say "ok!";

my $home = File::HomeDir->my_home;;
my $storage = "$home/.memento";
if (!-d $storage) {
  say "\n>> Creating ~/.memento folder";
  mkdir($storage) or die "Cannot create .memento dir in your home directory: $!\n";
}

if (!-f "/usr/local/bin/memento") {
  say "\n>> Creating memento symlink";
  `ln -s $cwd/memento.pl /usr/local/bin/memento`;
}

say "\nMemento installation finished.";
