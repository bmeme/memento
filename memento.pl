#!/usr/bin/perl
$file = `which memento`;
$_ = `ls -l $file`;
if (/ (\/[\w\/\-]+?memento\.pl)$/) {
  $dir = $1;
  $dir =~ s/\/memento.pl$//;
}
require "$dir/Memento.pm";

if ($#ARGV > -1) {
  my $memento = {}; bless $memento, "Memento";
  my $command = shift(@ARGV);
  $memento->$command(@ARGV);
}
else {
  print "._____.___ ._______._____.___ ._______.______  _____._._______\n"
       .":         |: .____/:         |: .____/:      \\ \\__ _:|: .___  \\\n"
       ."|   \\  /  || : _/\\ |   \\  /  || : _/\\ |       |  |  :|| :   |  |\n"
       ."|   |\\/   ||   /  \\|   |\\/   ||   /  \\|   |   |  |   ||     :  |\n"
       ."|___| |   ||_.: __/|___| |   ||_.: __/|___|   |  |   | \\_. ___/\n"
       ."      |___|   :/         |___|   :/       |___|  |___|   :/\n"
       ."                                                         :\n";
  print "Version: 0.1-alpha - 2015 - © Adriano Cori.\n";
}
