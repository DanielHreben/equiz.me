#!/usr/bin/env perl

use v5.14;
use strict;
use warnings;
use utf8;

BEGIN {
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use DBI;

use EQ::Model;

main();

sub main {
    EQ::Model->init( get_model_config() );

    migrate_instructors();
    migrate_sudents();
    migrate_results();
}

sub migrate_instructors {
    say 'MIGRATING INSTRUCTORS';
    migrate(
        EQ::Model::Storages->get_file_storage('instructors'),
        EQ::Model::Storages->get_dbi_storage('instructors'),
        'user_id'
    );
}

sub migrate_sudents {
    say 'MIGRATING STUDENTS';
    migrate(
        EQ::Model::Storages->get_file_storage('students'),
        EQ::Model::Storages->get_dbi_storage('students'),
        'user_id'
    );
}

sub migrate_results {
    say 'MIGRATING RESULTS';
    migrate(
        EQ::Model::Storages->get_file_storage('students_results'),
        EQ::Model::Storages->get_dbi_storage('students_results'),
        'result_id'
    );
}

sub migrate {
    my ($src, $dst, $key) = @_;
    die 'WRONG SRC STORAGE' unless $src && $src->isa('Hash::Storage');
    die 'WRONG DST STORAGE' unless $src && $src->isa('Hash::Storage');
    die 'KEY REQUIRED' unless $key;

    foreach my $hash ( @{ $src->list() } ) {
        unless ( $hash->{$key} ) {
            warn Dumper $hash;
            die "NO VALUE FOR [$key]";
        }

        delete( $hash->{_id} );
        say "processing [$hash->{$key}]";
        $dst->set( $hash->{$key}, $hash);
    }

    say "SUCCESS \n";
}

sub get_model_config {
    my $conf_path = "$FindBin::Bin/../etc/eq.conf";
    my $config    = do $conf_path;
    die $@ if $@;
    return $config->{model};
}