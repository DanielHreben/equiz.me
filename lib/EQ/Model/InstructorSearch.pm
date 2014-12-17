package EQ::Model::InstructorSearch;

use v5.14;

use strict;
use warnings;

use Digest::MD5 ();

use EQ::Model::Instructors;

sub new {
    my $class = shift;
    my (%params) = @_;

    my $self = {};
    bless $self, $class;

    $self->{backend} = $params{backend} || die 'backend is required';
    $self->{limit}   = $params{limit}   || 100;

    return $self;
}

sub search {
    my $self = shift;
    my ($query) = @_;

    my $backend = $self->{backend};

    my @instructors =
      map {
        {
            id          => $_->{email},
            name        => $_->{first_name} . ' ' . $_->{last_name},
            email       => $_->{email},
            institution => $_->{institution},
        }
      } @{EQ::Model::Instructors->get_all_instructors};

    my @matches;

    my $limit = $self->{limit};

    foreach my $instructor (@instructors) {

        my $found = 0;
        foreach my $key (keys %$instructor) {
            next if $key eq 'id';

            if ($instructor->{$key} =~ s/(\Q$query\E)/<span style="color:red">$1<\/span>/imsg) {
                $found++;
            }
        }

        push @matches, $instructor if $found;
    }

    return \@matches;
}

1;
