package EQ::Model::StudentAccess;

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

    return $self;
}

sub is_email_permitted {
    my $self = shift;
    my ($instructor_id, $user_id) = @_;

    my $backend = $self->{backend};

    my @files= $backend->list_files($instructor_id);
    if ($backend->file_exists($instructor_id, 'permitted.emails')) {
        my $content = $backend->slurp_file($instructor_id, 'permitted.emails');
        my @emails = map { s/\s+$//; $_ } map { s/^\s+//; $_ } split /\n/,
          $content;
        if (!grep { $_ eq $user_id } @emails) {
            return 0;
        }
    }

    return 1;
}
1;
