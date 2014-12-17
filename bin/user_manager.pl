#!/usr/bin/env perl

use v5.14;
use strict;
use warnings;

BEGIN {
    use FindBin;

    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;

use Time::Piece;
use Hash::Storage;
use EQ::Model;
use EQ::Model::Students;

EQ::Model->init(get_model_config());

my ($command) = shift @ARGV;
my %commands = (
    'list'               => \&list,
    'list_by_last_login' => \&list_by_last_login,
    'show'               => \&show,
    'archive'            => \&archive,
    'restore'            => \&restore,
    'delete'             => \&delete_student,
);

if (!$command) {
    print "Available commands:\n";

    foreach my $command (keys %commands) {
        print "    ", $command, "\n";
    }

    exit 0;
}

die "Unknown command '$command'" unless my $sub = $commands{$command};

$sub->(@ARGV);

sub list {
    my $students = EQ::Model::Students->get_all_students();
    $students = [sort { $a->{email} cmp $b->{email} } @$students];

    foreach my $student (@$students) {
        print "$student->{email}\n";
    }
}

sub list_by_last_login {
    my $students = EQ::Model::Students->get_all_students();
    $students = [sort { $a->{last_login} cmp $b->{last_login} } @$students];

    foreach my $student (@$students) {
        my $last_login =
          Time::Piece->new($student->{last_login})->strftime('%Y-%m-%d %T');

        print "$student->{email} $last_login\n";
    }
}

sub show {
    my $student = _load_student(@_);

    use Data::Dumper;
    warn Dumper($student);
}

sub archive {
    my $student = _load_student(@_);

    EQ::Model::Students->archive_student($student);
}

sub restore {
    my $student = _load_student(@_);

    EQ::Model::Students->restore_student($student);
}

sub delete_student {
    my $student = _load_student(@_);

    EQ::Model::Students->delete_student($student);
}

sub _load_student {
    my ($student_id) = @_;

    die "student_id is required\n" unless $student_id;

    my $student = EQ::Model::Students->get_student($student_id);
    die "Unknown student\n" unless $student;
}

sub get_model_config {
    my $conf_path = "$FindBin::Bin/../etc/eq.conf";
    my $config    = do $conf_path;
    die $@ if $@;
    return $config->{model};
}
