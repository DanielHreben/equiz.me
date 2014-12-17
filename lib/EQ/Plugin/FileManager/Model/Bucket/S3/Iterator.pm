package EQ::Plugin::FileManager::Model::Bucket::S3::Iterator;

use v5.14;

use strict;
use warnings;

use base 'EQ::Plugin::FileManager::Model::Bucket::IteratorBase';

sub BUILDARGS {
    my $self = shift;
    my (%params) = @_;

    $self->{s3} = $params{s3};
}

sub _list_uids {
    my $self = shift;

    my $s3 = $self->{s3};

    my $buckets = $s3->buckets;

    return [map {$_->bucket} @{$buckets->{buckets}}];
}

sub _list_files {
    my $self = shift;
    my ($uid) = @_;

    my $s3 = $self->{s3};

    my $bucket = $s3->bucket($uid);

    my @files;

    my $response = $bucket->list_all or die $s3->err . ": " . $s3->errstr;
    foreach my $key (@{$response->{keys}}) {
        my $key_name = $key->{key};

        push @files, $key_name;
    }

    return [@files];
}

1;
