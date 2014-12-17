#!/usr/bin/env perl

use v5.14;
use strict;
use warnings;
use utf8;

use File::Path qw/remove_tree make_path/;
use Time::Piece;

# CAUTION
# THIS SCRIPT IS A QUICK SOLUTION FOR EQUIZ BACKUP
# IT SUPPORT ONLY MYSQL USER STORAGE (DATABASE NAME HARDCODED 'EQ')

BEGIN {
    use FindBin qw/$Bin/;
    use lib "$Bin/../lib";
}

use constant MAX_BACKUP_FILES => 10;

main();

sub main {
    my $config = get_app_config();

    my $backup_dir = "$Bin/../backup";
    my $backup_tmp_dir = "$backup_dir/tmp";

    remove_tree($backup_tmp_dir);
    make_path($backup_tmp_dir);

    backup_mysql_db(
        user        => $config->{model}{storage_db}{username},
        password    => $config->{model}{storage_db}{password},
        db          => 'eq', # TODO Should be taken from config
        backup_dir  => $backup_tmp_dir
    );

    backup_file_manager(
        file_manager_dir => $config->{file_manager}{root_dir},
        backup_dir       => $backup_tmp_dir
    );


    my $date = localtime->ymd();
    my $cmd = "tar czf ${backup_dir}/equiz-$date.tgz $backup_tmp_dir";
    system($cmd) == 0 or die "Cannot execute [$cmd]. $!";

    say "Created backup for equiz [${backup_dir}/equiz-$date.tgz]";

    remove_outdated_backups(
        backup_dir => $backup_dir
    );
}


sub backup_file_manager {
    my %args = @_;

    die $! unless -d $args{file_manager_dir};
    die $! unless -d $args{backup_dir};

    my $cmd = "tar cf $args{backup_dir}/storage.tar $args{file_manager_dir}";

    system($cmd) == 0 or die "Cannot execute [$cmd] $!"
}

sub backup_mysql_db {
    my %args = @_;

    die "user required" unless $args{user};
    die "password required" unless defined $args{password};
    die "db required" unless $args{db};
    die "backup_dir required" unless $args{backup_dir};


    my $cmd = "mysqldump --user $args{user} --password='$args{password}' --database $args{db} > $args{backup_dir}/equiz.sql";

    system($cmd) == 0 or die "Cannot execute [$cmd] $!";
}

sub remove_outdated_backups {
    my %args = @_;

    die $! unless -d $args{backup_dir};

    opendir( my $dh, $args{backup_dir} ) or die "Cannot read [$args{backup_dir}] $!";
    my @files = sort grep { /\.tgz$/ } readdir($dh);
    closedir $dh;

    while( @files > MAX_BACKUP_FILES ) {
    	my $file = "$args{backup_dir}/" . shift @files;

    	if ( unlink $file ) {
    		say "Old backup file [$file] war removed";
    	} else {
    		say "Cannot remove file [$file] $!";
    	}
    }

}

sub get_app_config {
    my $conf_path = "$Bin/../etc/eq.conf";
    my $config    = do $conf_path;
    die $@ if $@;
    return $config;
}