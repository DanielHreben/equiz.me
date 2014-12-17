package EQ::Plugin::FileManager::Model::Bucket::FileSystem::Iterator;

use v5.14;

use strict;
use warnings;

use base 'EQ::Plugin::FileManager::Model::Bucket::IteratorBase';

use File::Spec;

sub BUILDARGS {
    my $self = shift;
    my (%params) = @_;

    $self->{root} = $params{root};
}

sub _list_uids {
    my $self = shift;

    opendir my $dh, $self->{root} || die "can't opendir $self->{root}: $!";
    my @uids = sort grep { !m/^\./ && -d "$self->{root}/$_" } readdir($dh);
    closedir $dh;

    return [@uids];
}

sub _list_files {
    my $self = shift;
    my ($uid) = @_;

    my $path = File::Spec->catfile( $self->{root}, $uid );
    opendir my $dh, $path || die "can't opendir $path: $!";

    my $files = [grep { -f "$path/$_" && !m/^\./ } readdir $dh];

    closedir $dh;

    return $files;
}

1;
