#!/usr/bin/env perl
use strict; use warnings;

sub get_vendors {
  return (
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
}

1;