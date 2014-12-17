package EQ::Model::Quizzes;

use v5.14;

use strict;
use warnings;

use Text::CSV;
use File::Slurp;
use Data::UUID;
use Digest::MD5 qw/md5_hex/;
use Data::Dumper;
use EQ::Plugin::FileManager::Model::Bucket;

sub check_id {
    my ($class, $quiz_id) = @_;
    return $quiz_id =~ /^[a-zA-Z0-9][a-zA-Z0-9_\@\-.+]*[a-zA-Z0-9]$/ ? 1 : 0;
}


sub get_quizzes_for_instructor {
    my ( $class, $instructor_id ) = @_;

    my @quizzes;

    my $backend = EQ::Plugin::FileManager::Model::Bucket->backend;

    my @files = $backend->list_files($instructor_id);

    foreach my $file (@files) {
        if ($file =~
            /
                ^
                (?<quiz_id>
                    (?<name>\w(?:[\w\@\-]+)?)
                    (?<date> \.? (?<year>20\d\d) (?<month>\d\d) (?<day>\d\d) ) ?)
                \.quiz
                $
            /x
          )
        {
            my $date = $+{date} ? "$+{month}/$+{day}/$+{year}" : '';

            push(
                @quizzes,
                {
                    quiz_id => $+{quiz_id},
                    name    => $+{name},
                    date    => $date,
                }
            );
        }
    }

    return  \@quizzes;
}

1;
