use strict;
use warnings;

use lib './inc';

use Test::Run::Builder;

my $builder = Test::Run::Builder->new(
    module_name         => 'Text::Table',
    license             => 'mit',
    dist_author         => 'Shlomi Fish <shlomif@cpan.org>',
    dist_version_from   => 'lib/Text/Table.pm',
    configure_requires =>
    {
        'Module::Build' => 0.36,
    },
    build_requires => {
        'List::Util' => 0,
        'Test::More' => 0,
    },
    requires => {
        'perl' => '5.008',
        'strict' => 0,
        'warnings' => 0,
        'Text::Aligner' => '0.05',
    },
    add_to_cleanup      => [ 'Text-Table-*' ],
    create_makefile_pl => 'traditional',
    meta_merge =>
    {
        resources =>
        {
            repository => "https://github.com/shlomif/Text-Table",
        },
        keywords =>
        [
            "art",
            "ascii",
            "asciiart",
            "borders",
            "table",
            "text",
            "unicode",
        ],
    },
);

$builder->create_build_script();
