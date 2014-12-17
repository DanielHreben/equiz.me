package EQ::Plugin::FileManager::Model::Bucket::IteratorBase;

use v5.14;

use strict;
use warnings;

sub new {
    my $class = shift;
    my (%params) = @_;

    my $self = {};
    bless $self, $class;

    $self->BUILDARGS(%params);

    $self->{files} = [];

    $self->{uids} = $self->_list_uids;

    return $self;
}

sub next {
    my $self = shift;

    my $uid = $self->{uid};

    if (!@{$self->{files}}) {
        $uid = $self->{uid} = $self->_next_uid;
    }

    return () unless $uid;

    my $file = shift @{$self->{files}};

    return () unless $file;

    return ($uid, $file);
}

sub _next_uid {
    my $self = shift;

    my $uid = shift @{$self->{uids}};
    return unless $uid;

    $self->{files} = $self->_list_files($uid);

    return $uid;
}

sub _list_uids {
    my $self = shift;

    die 'overwrite';
}

sub _list_files {
    my $self = shift;
    my ($uid) = @_;

    die 'overwrite';
}

1;
