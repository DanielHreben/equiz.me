package EQ::Model::Students;

use v5.14;

use strict;
use warnings;

sub _storage { EQ::Model::Storages->get_students_storage() }


sub get_all_students {
  my $class = shift;
  return $class->_storage->list();
}

sub get_students_for_leaderboard {
  my $class = shift;
  return $class->_storage->list([ is_enabled_leaderboard => 1 ]);
}

sub get_student {
  my $class = shift;
  return $class->_storage->get(@_);
}

sub archive_student {
  my $class = shift;
  my ($student) = @_;

  $student->{_is_activated_by_admin} = 0;

  $class->_storage->set($student->{email}, $student);
}

sub restore_student {
  my $class = shift;
  my ($student) = @_;

  $student->{_is_activated_by_admin} = 1;

  $class->_storage->set($student->{email}, $student);
}

sub delete_student {
  my $class = shift;
  my ($student) = @_;

  $class->_storage->del($student->{email});
}

1;
