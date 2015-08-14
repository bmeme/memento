#!/usr/bin/perl
use strict; use warnings;
use feature 'say';
use Cwd;

our $cwd = cwd;
my @vendors = (
  'Text-Aligner',
  'Text-Table'
);

foreach my $vendor (@vendors) {
  &installVendor($vendor);
}

sub installVendor() {
  my $vendor = shift;
  print "[$vendor] installing vendor...\n";
  my $dir = "$cwd/vendor/$vendor";

  if (-d $dir) {
    # exec install.
    chdir $dir;
    say `perl Build.PL`;
    say `./Build`;
    say `./Build test`;
    say `./Build install`;

    # generate vendor lib directory.
    my $lib = "$dir/lib";
    chdir $lib;

    opendir(D, "$lib") || die "Can't open directory $lib: $!\n";
    my @list = readdir(D);
    closedir(D);

    my $lib_dir = $list[2] || die "Empty lib directory: $!\n";
    if (!-d "$cwd/$lib_dir") {
      print "Lib dir $lib_dir not found: creating directory...";
      mkdir("$cwd/$lib_dir") or die "error: $!\n";
      say "done!";
    }

    # create symlinks.
    $lib = "$lib/$lib_dir";
    chdir $lib;
    opendir(D, "$lib") || die "Can't open directory $lib: $!\n";
    @list = grep /\.pm?$/, readdir(D);
    closedir(D);

    chdir "$cwd/$lib_dir";
    say "Generating symlinks...";
    foreach my $lib_file (@list) {
      say $lib_file;
      `ln -s vendor/$vendor/lib/$lib_dir/$lib_file $lib_file`;
    }
  }
  else {
    say "Could not install vendor $vendor: $!";
    die "Installation aborted. Please verify memento code is up to date and retry.\n";
  }
}
