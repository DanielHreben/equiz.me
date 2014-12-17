#!/usr/bin/env perl

use v5.14;
use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Getopt::Long;
use Data::Dumper;
use File::Spec::Functions;
use Digest::MD5 qw/md5_hex/;
use File::stat;
use Time::Piece;
use File::Slurp;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use MIME::Lite;
use Hash::Storage;

use EQ::Model;
use EQ::Model::Instructors;
use EQ::Plugin::FileManager::Model::Bucket::FileSystem;

my $config = get_config();
EQ::Plugin::FileManager::Model::Bucket->setup(%{$config->{file_manager}});

my $backend = EQ::Plugin::FileManager::Model::Bucket->backend;

EQ::Model->init($config->{model});

my $instructors = EQ::Model::Instructors->get_all_instructors();
foreach my $instructor (@$instructors) {
    email_backup($instructor);
}

sub get_config {
    my $conf_path = "$FindBin::Bin/../etc/eq.conf";
    my $config    = do $conf_path;
    die $@ if $@;
    return $config
}

sub email_backup {
    my ($instructor) = @_;

    my $user_id = $instructor->{user_id};
    my $uid = $backend->resolve_uid($user_id);

    my $ts_file  = "$uid.timestamp";
    my $zip_file = "/tmp/$uid.zip";

    my $ts = $backend->file_exists($ts_file) ? $backend->get_file_mtime($ts_file) : 0;

    my @backup_files;
    foreach my $file ($backend->list_files($user_id)) {
        if ($backend->get_file_mtime($user_id, $file) > $ts) {
            push @backup_files, $file;
        }
    }

    return unless @backup_files;

    my $mdy      = localtime->mdy('-');
    my $filename = "equiz-" . $mdy . '.zip';

    if (archieve_files($zip_file, $filename, $user_id, \@backup_files)) {
        send_email(
            {   from      => '',
                to        => $instructor->{email},
                subject   => 'Equiz daily digest ' . $mdy,
                body      => 'Equiz daily digest ' . $mdy,
                file      => $zip_file,
                file_name => $filename,
            }
        );

        $backend->write_file($ts_file, time);

        unlink($zip_file);
    }
    else {
        # write error to log
    }
}

sub archieve_files {
    my ($zip_file, $filename, $user_id, $files) = @_;

    $filename =~ s/\.[^\.]+$//;

    my $arch = Archive::Zip->new();
    $arch->addDirectory($filename);
    for my $file (@$files) {
        my $content = $backend->slurp_file($user_id, $file);
        my $dest = $file;
        $arch->addString($content, "$filename/$dest");
    }

    say $zip_file;
    if ($arch->writeToFileNamed($zip_file) == AZ_OK) {
        say 1;
        return 1;
    }
    else {
        say 0;

        #write error to log
        return 0;
    }
}

sub send_email {
    my $data = shift;
    print Dumper $data;
    MIME::Lite->send("sendmail", "/usr/lib/sendmail -t");
    my $msg = MIME::Lite->new(
        From    => $data->{from},
        To      => $data->{to},
        Subject => $data->{subject},
        Type    => 'text/plain; charset=utf-8',
        Data    => $data->{body}
    );

    if ($data->{file}) {
        $msg->attach(
            Type        => 'application/octet-stream',
            Path        => $data->{file},
            Filename    => $data->{file_name} || basename($data->{file}),
            Disposition => 'attachment'
        );
    }

    $msg->send();
}
