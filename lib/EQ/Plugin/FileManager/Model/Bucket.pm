package EQ::Plugin::FileManager::Model::Bucket;

use v5.14;

use strict;
use warnings;

use EQ::Plugin::FileManager::Model::Bucket::FileSystem;
use EQ::Plugin::FileManager::Model::Bucket::S3;

our $backend;

sub setup {
    my $class = shift;

    $backend = $class->build(@_);
}

sub build {
    my $class = shift;
    my (%params) = @_;

    my $type = $params{type} ||= 'FileSystem';

    my $backend_class = __PACKAGE__ . '::' . $type;

use v5.14;
    return $backend_class->new(%params);
}

sub backend {$backend}

1;
