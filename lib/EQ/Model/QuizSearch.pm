package EQ::Model::QuizSearch;

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

    my $instructors = $self->_get_instructors;

    my @matches;

    my $limit = $self->{limit};

    my $iterator = $backend->get_file_iterator;
  MATCH: while (my ($uid, $file) = $iterator->next) {
        next unless $file =~ m/\.(?:testbank|quiz)$/;

        my $content = $backend->slurp_file($uid, $file);
        next if $content =~ m/^::LICENSE::.*PRIVATE/smi;

        next unless $content =~ m/\Q$query\E/ims;

        my $author;
        while ($content =~ /^(:N:.*?^:E:)/msg) {
            my $question = $1;

            next
              unless $question =~
                  s/(\Q$query\E)/<span style="color:red">$1<\/span>/imsg;

            $author ||= $instructors->{$uid};
            next MATCH unless $author;

            push @matches,
              {
                author   => $author->{name},
                email    => $author->{email},
                question => $question
              };

            $limit--;
            last MATCH unless $limit;
        }
    }

    return \@matches;
}

sub search_quizzes {
    my $self = shift;
    my ($query) = @_;
    my $backend = $self->{backend};

    my $instructors = $self->_get_instructors;

    my @matches;

    my $limit = $self->{limit};

    my $iterator = $backend->get_file_iterator;
  MATCH: while (my ($uid, $file) = $iterator->next) {
        next unless $file =~ m/\.(?:testbank|quiz)$/;

        my $content = $backend->slurp_file($uid, $file);
        next if $content =~ m/^::LICENSE::.*PRIVATE/smi;

        next unless my ($title) = $content =~ m/^::NAME::(.*)/i;

        next unless $content =~ m/\Q$query\E/ims;

        my $author;
        while ($content =~ /^(:N:.*?^:E:)/msg) {
            my $question = $1;

            next unless $question =~ m/(\Q$query\E)/imsg;

            $author ||= $instructors->{$uid};
            next MATCH unless $author;

            my ($quiz_id) = $file =~ /^(?<quiz_id> (?<name>\w[\w\@\-]+))/x;

            push @matches,
              {
                author        => $author->{name},
                email         => $author->{email},
                instructor_id => $author->{email},
                quiz_id       => $quiz_id,
                title         => $title
              };

            last;
        }

        $limit--;
        last MATCH unless $limit;
    }

    return \@matches;
}

sub _get_instructors {
    my $self = shift;

    my @instructors =
      map {
        {
            name  => $_->{first_name} . ' ' . $_->{last_name},
            email => $_->{email}
        }
      } @{EQ::Model::Instructors->get_all_instructors};
    my $instructors = {};
    foreach my $instructor (@instructors) {
        $instructors->{Digest::MD5::md5_hex($instructor->{email})} =
          $instructor;
    }

    return $instructors;
}

1;
