package EQ::Model::Instructors;

use v5.14;

use strict;
use warnings;

use EQ::Model::Storages;

sub _storage { EQ::Model::Storages->get_instructors_storage() }

sub check_id {
    my ( $class, $instructor_id ) = @_;

    die "Wrong instructor id [$instructor_id]"
      unless $instructor_id =~ /^[a-zA-Z0-9][a-zA-Z0-9_\@\-.+]*[a-zA-Z0-9]$/;
}

sub get_all_instructors {
    my $class = shift;

    my $instructors = $class->_storage->list();

    return $instructors;
}

sub get_instructor {
    my ( $class, $instructor_id ) = @_;

    $class->check_id($instructor_id);

    return $class->_storage->get($instructor_id);
}

1;
