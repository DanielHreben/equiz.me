package EQ::Model::Storages;

use v5.14;

use strict;
use warnings;

use File::Spec::Functions qw/catdir/;
use File::Path qw/make_path/;

use Hash::Storage;
use DBI;
use experimental 'smartmatch';

sub get_file_storage {
    my ($self, $storage_name) = @_;

    die "WRONG STORAGE NAME"
        unless $storage_name ~~ [qw/instructors students students_results/];

    my $dirs = {
        'instructors'      => 'instructor',
        'students'         => 'student',
        'students_results' => 'students_results',
    };

    my $config = EQ::Model->get_config();

    my $dir = catdir( $config->{storage_root}, $dirs->{$storage_name} );

    unless ( -e $dir ) {
        make_path($dir) or die "Cannot create dir [$dir] $!";
    }

    my $st = Hash::Storage->new( driver => [ Files => {
        serializer => 'JSON',
        dir        => $dir,
    } ] );

    return $st;
}


sub get_dbi_storage {
    my ($class, $storage_name) = @_;
    die "WRONG STORAGE NAME"
        unless $storage_name ~~ [qw/instructors students students_results/];

    my $conf = EQ::Model->get_config();
    die "DSN REQUIRED" unless  $conf->{storage_db}{dsn};

    state $index_columns = {
        instructors => [qw/
            _activation_code_for_user
            _activation_code_for_admin
            _autologin_code
        /],
        students => [qw/
            _activation_code_for_user
            _activation_code_for_admin
            _autologin_code
            is_enabled_leaderboard
        /],
        students_results => [qw/
            student_id
            submit_time
        /],
    };

    my $dbh = DBI->connect(
        $conf->{storage_db}{dsn},
        $conf->{storage_db}{username},
        $conf->{storage_db}{password},
        $conf->{storage_db}{params},
    );


    my $st = Hash::Storage->new( driver => [ DBI => {
        serializer    => 'JSON',
        dbh           => $dbh,
        table         => $storage_name,
        key_column    => 'id',
        data_column   => 'serialized',
        index_columns => $index_columns->{$storage_name},
    } ] );

    return $st;
}

sub get_storage {
    my ($class, $storage_name) = @_;
    die "WRONG STORAGE NAME"
        unless $storage_name ~~ [qw/instructors students students_results/];

    my $conf = EQ::Model->get_config();
    my $driver = lc($conf->{storage_driver});

    if ( $driver eq 'dbi' ) {
        return $class->get_dbi_storage($storage_name);
    }
    elsif ( $driver eq 'files' ) {
        return $class->get_file_storage($storage_name);
    }
    else {
        die "WRONG DRIVER [$driver]";
    }
}

sub get_instructors_storage {
    my $class = shift;

    state $storage = $class->get_storage('instructors');
    return $storage;
}

sub get_students_storage {
    my $class = shift;

    state $storage = $class->get_storage('students');
    return $storage;
}

sub get_results_storage {
    my $class = shift;

    state $storage = $class->get_storage('students_results');
    return $storage;
}

1;