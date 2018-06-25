#!/usr/bin/env perl
use strict; use warnings;
use feature 'say';
use Cwd;
use Getopt::Long;
use Pod::Usage;

our $cwd = getcwd();
my $cpan_path = `which cpan`;
my $bin_dir = "/usr/local/bin";

if (!$cpan_path) {
  say "Please install cpan command line tool in order to proceed with the installation.";
  say "http://www.cpan.org/modules/INSTALL.html\n";
  die "Installation aborted.\n";
}

GetOptions(
  'bin-dir=s' => \$bin_dir,
  q(help) => \my $help,
) or die 'Incorrect usage';
pod2usage(q(-verbose) => 1) if $help;

say ">> Checking requirements:";
if (!-d $bin_dir) {
  say "'$bin_dir' directory not found, creation in progress...";

  if (!mkdir($bin_dir)) {
    say "Not enough permissions for creation of '$bin_dir' directory. Retrying with sudo...";
    my $user = `whoami`;
    my $group = `id -gn`;
    chomp($user);
    chomp($group);

    `sudo mkdir -p $bin_dir`;
    if (!-d $bin_dir) {
      die("There was a problem while creating '$bin_dir' directory. Please create it and set writable permissions and then try again.\n");
    }

    `sudo chown -R $user:$group $bin_dir`;
    `sudo chmod u+w $bin_dir`;
    `sudo chmod g+w $bin_dir`;
  }

  say "'$bin_dir' directory successfully created.";
}
say "Requirements are ok! Proceeding with the installation.";

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
  'JIRA::REST',
  'Net::SSLeay',
  'LWP::UserAgent',
  'LWP::Protocol::https',
  'MIME::Base64',
  'Switch',
  'FLORA/Term-Complete-1.402.tar.gz',
  'Term::ANSIColor',
  'Text::Aligner',
  'Text::ASCIITable',
  'Text::Table',
  'Text::Trim',
  'Text::Unidecode'
);

foreach my $vendor (@vendors) {
  say "\n>> Installing [$vendor]";
  my $options = ($^V lt 'v5.18.0') ? '-i -f' : '-i -T';
  say "▶ cpan $options $vendor";
  system("cpan $options $vendor");
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
          system("sudo patch -sN $full_path $patches_dir/$patch");
        }
      }
    }
  }
}

print "\n>> Generating Memento man page: ";
my $man_dir = $cpan_path;
chomp($man_dir);
$man_dir =~ s/\/bin\/cpan$//;
my $man = `pod2man -s 1 -c Memento memento.pl | sudo tee -a $man_dir/share/man/man1/memento.1`;
say "ok!";

chdir;
my $home = getcwd();
my $storage = "$home/.memento";
if (!-d $storage) {
  say "\n>> Creating ~/.memento folder";
  mkdir($storage) or die "Cannot create .memento dir in your home directory: $!\n";
}

if (!-f "$bin_dir/memento") {
  say "\n>> Creating memento symlink";
  `sudo ln -s $cwd/memento.pl $bin_dir/memento`;
}

say "\nMemento installation finished.";
say "Please add the following line to your .bashrc or .zshrc file:\n";
say "\tmemento schema check\n";

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

memento install

=head1 VERSION

version 1.0.0.1

=head1 USAGE

The installation script must be run in the following way:

"perl install.pl" or "./install.pl":

=over 2

=item --bin-dir

Can be used to define a custom bin directory. If not set "/usr/local/bin" will
be used as the default one.

=back

=cut
