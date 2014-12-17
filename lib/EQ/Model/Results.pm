package EQ::Model::Results;

use v5.14;

use strict;
use warnings;

use Text::CSV;
use File::Slurp;
use Data::UUID;
use Digest::MD5 qw/md5_hex/;

sub _storage { EQ::Model::Storages->get_results_storage() }

sub check_id {
    my ( $class) = @_;
    die "Wrong Result ID [$_[1]]" unless $_[1] =~ /^\s*[A-F0-9\-]{36}$/i;

    $_[1] =~ s{^\s*}{};
}

sub get_all_results {
	my $class = shift;
	return $class->_storage->list();
}

sub get_results_for_student {
    my ($class, $student_id) = @_;
    die "Wrong student id [$student_id]" unless $student_id;

    # Filter only the student results
    my $student_results = $class->_storage->list(
        where   => [ student_id => $student_id ],
        sort_by => 'submit_time DESC'
    );

    # Calculate percentage
    foreach my $res ( @$student_results ) {
       $res->{submit_time} = localtime( $res->{submit_time} );

       if ( $res->{max_score} > 0 ) {
           $res->{percentage} = sprintf('%0.2f', 100 * $res->{score} / $res->{max_score});
       } else {
           $res->{percentage} = '0.00';
       }
    }

    return $student_results;
}


sub get_result {
	my ($class, $result_id) = @_;
    $class->check_id($result_id);

    my $res = $class->_storage->get($result_id);
    return $res;
}

sub get_leaderboard_for_quiz {
    my ($class, $quiz_id) = @_;
    EQ::Model::Quizzes->check_id($quiz_id);

    # Find all students that participate in leaderboard
    my %students = map {
        $_->{user_id} => $_
    } @{ EQ::Model::Students->get_students_for_leaderboard() };

    my @top_results =
       sort { $b->{submit_time} <=> $a->{submit_time} }
       grep { $_->{score} == $_->{max_score} } @{ $class->_storage->list(); };


    my @leaderboard;
    foreach my $res ( @top_results ) {
        next unless exists $students{ $res->{student_id} };
        my $st_data = $students{ $res->{student_id} };

        $res->{submit_time} = localtime( $res->{submit_time} );
        $res->{student_name} = "$st_data->{first_name} $st_data->{last_name}";
        push @leaderboard, $res;
    }

    return \@leaderboard;
}

sub save_quiz_result {
    my $class = shift;
    my (%params) = @_;

    my $quiz_id       = $params{quiz_id}       || die 'quiz_id required';
    my $instructor_id = $params{instructor_id} || die 'instructor_id required';
    my $student_id    = $params{user_id}       || die 'user_id required';
    my $student_ip    = $params{user_ip}       || die 'user_ip required';
    my $start_time    = $params{start_time}    || die 'start_time required';
    my $submit_time   = $params{finish_time}   || die 'finish_time required';
    my $results       = $params{results}       || die 'results required';

    my $user_name = $student_id;
    my $result_id = Data::UUID->new()->create_str();

    # Append line to CSV results file in instructor home
    my @columns = ($result_id, $start_time, $submit_time, $quiz_id, $student_id, $user_name, $student_ip );
    push @columns, map { $_->{is_correct} } @$results;

    my $csv = Text::CSV->new ( { binary => 1 } );
    my $csv_line =  $csv->combine(@columns) ? $csv->string() : 'N/A';

    my $backend = EQ::Plugin::FileManager::Model::Bucket->backend;

    $backend->append_file($instructor_id, "$quiz_id.results.csv", $csv_line);

    # Update quiz results instructors log
    $backend->append_file(
        $instructor_id,
        'quizzes.timelog',
        "QUIZFINISH=[$submit_time] STUDENT=[$student_id] INSTRUCTOR=[$instructor_id] QUIZ=[$quiz_id] RESULT=[$result_id]"
    );

    # Save results in global results storage
    my $instuctor = EQ::Model::Instructors->get_instructor($instructor_id);

    $class->_storage->set( $result_id, {
        instructor_id   => $instructor_id,
        quiz_id         => $quiz_id,
        student_id      => $student_id,
        submit_time     => $submit_time,
        result_id       => $result_id,
        is_print_answer => $instuctor->{is_print_answer},
        max_score       => scalar( @$results ),
        score           => scalar( grep { $_->{is_correct} } @$results ),
        full_result     => $results,
    });
}


1;
