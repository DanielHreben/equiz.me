package EQ::Controller::Students;

use v5.14;

use strict;
use warnings;

use Mojo::Base 'Mojolicious::Controller';

use File::Spec::Functions qw/catdir catfile/;
use Fcntl qw/:flock/;
use File::Slurp qw/write_file/;
use Data::Dumper;
use Time::Piece;
use Text::CSV;
use Digest::MD5 qw/md5_hex/;
use Try::Tiny;

use EQ::Quiz;
use EQ::Model::QuizSearch;
use EQ::Model::InstructorSearch;
use EQ::Model::StudentAccess;

sub _run {
    my ($self, $cb) = @_;

    try {
        $cb->();
    }
    catch {
        my $error = $_;
        $error =~ s{ at [\S]+ line \d+.}{};
        $self->flash('error' => $error)->redirect_to('students_show_home');
    };
}

#################################### PUBLIC METHODS ####################################

# Show student's main screen
sub show_home {
    my $self = shift;

    $self->_run( sub {
        my $instructor_id = $self->user_data->{instructor_id};

        # Default data
        my $data = {
            default_instructor_name   => 'unknown instructor',
            is_enabled_leaderboard    => 0,
            message                   => '',
            quizzes                   => [],
            numquizzes                => 0,
            instructor_name           => 'unknown instructor',
            instructor_course         => 'unknown course',
            instructor_instructorsite => '',
            instructor_coursesite     => '',
        };

        # Instructor data
        my $instructor = try { EQ::Model::Instructors->get_instructor($instructor_id) };
        if ($instructor) {
            my $remove_http = sub {
                my $url = shift;
                return '' unless $url;

                $url =~ s/^http:\/\///i;
                return $url;
            };

            my $instructor_name = "$instructor->{first_name} $instructor->{last_name}";
            my $quizzes = EQ::Model::Quizzes->get_quizzes_for_instructor($instructor_id);

            my $results = EQ::Model::Results->get_results_for_student( $self->user_data('user_id') );
            my %results;
            foreach my $result (@$results) {
                $results{$result->{quiz_id}}++;
            }
            foreach my $quiz (@$quizzes) {
                if (exists $results{$quiz->{quiz_id}}) {
                    $quiz->{is_submitted} = 1;
                }
            }

            $data = {
                default_instructor_name   => $instructor_name,
                is_enabled_leaderboard    => $instructor->{is_enabled_leaderboard} ,
                message                   => $instructor->{message},
                quizzes                   => $quizzes,
                numquizzes                => scalar(@$quizzes),
                instructor_name           => $instructor_name,
                instructor_course         => $instructor->{class} || 'unknown course',
                instructor_instructorsite => $remove_http->($instructor->{instructorsite}),
                instructor_coursesite     => $remove_http->($instructor->{coursesite}),

            };
        }

        $self->render( %$data );
    });
}

sub show_full_results {
    my $self = shift;

    $self->_run( sub {
        my $result_id = $self->param('result_id');
        my $result = EQ::Model::Results->get_result($result_id);

        if ( $result->{is_print_answer} ) {
            return $self->render( 'students/show_quiz_results', results => $result->{full_result} );
        } else {
            return $self->redirect_to('students_show_results');
        }
    });
}

# Show page with instructors to select quiz
sub show_instructors {
    my $self = shift;

    $self->_run( sub {
        my $instructors = EQ::Model::Instructors->get_all_instructors();
        $self->render( instructors => $instructors );
    });
}


# Show selected instructor's quizzes
sub show_quizzes {
    my $self = shift;

    $self->_run( sub {
        my $instructor_id = $self->param('instructor_id');
        my $instructor = EQ::Model::Instructors->get_instructor($instructor_id);

        # Check Password
        unless ( $self->_check_saved_qdl_password($instructor_id) ) {
            return $self->flash( error => 'Enter correct password' )->redirect_to('students_qdl_pass_update_form');
        }

        my $quizzes = EQ::Model::Quizzes->get_quizzes_for_instructor($instructor_id);
        my $results = EQ::Model::Results->get_results_for_student( $self->user_data('user_id') );

        # Find last result for each quiz
        # results are already sorted by date
        foreach my $quiz (@$quizzes) {
            foreach my $res (@$results) {
                if ($quiz->{quiz_id} eq $res->{quiz_id}) {
                    $quiz->{last_result} = $res->{percentage};
                    last;
                }
            }
        }

        $self->render(
            is_enabled_leaderboard => $instructor->{is_enabled_leaderboard},
            message => $instructor->{message},
            quizzes => $quizzes,
            numquizzes => scalar( @$quizzes ),
            instructor_name => "$instructor->{first_name} $instructor->{last_name}",
        );
    });
}

# Show quiz to student
sub show_quiz {
    my $self = shift;

    $self->_run( sub {
        my $instructor_id = $self->param('instructor_id');
        my $quiz_id = $self->param('quiz_id');

        EQ::Model::Instructors->check_id($instructor_id);
        EQ::Model::Quizzes->check_id($quiz_id);

        $self->session( quiz_id => $quiz_id, instructor_id => $instructor_id, start_time => time() );

        # Check qdl password
        unless ( $self->_check_saved_qdl_password($instructor_id) ) {
            return $self->flash( error => 'Enter correct password' )->redirect_to('students_qdl_pass_update_form');
        }

        # Check rup password
        unless ( $self->_check_saved_rup_password($instructor_id) ) {
            if ( $self->flash('is_force_quiz_start') ) {
                $self->stash( error => "You cannot submit this quiz because you've skipped password verification" );
            } else {
                return $self->flash( error => 'Enter correct password' )->redirect_to('students_rup_pass_update_form');
            }
        }

        my $quiz_filename = "$quiz_id.quiz";
        return $self->render( text => "Wrong quiz id [$quiz_id]") unless $self->backend->file_exists($instructor_id, $quiz_filename);

        # Prepare quiz html
        my $user_data = $self->user_data;
        my $iid = $user_data->{user_id};
        my $uid = $user_data->{user_id};
        my $tid = $quiz_id;

        if (!$self->_is_email_permitted($instructor_id, $user_data->{user_id})) {
            die 'You are not permitted to view/submit this quiz';
        }

        my $quiz_content = $self->backend->slurp_file($instructor_id, $quiz_filename);
        my $quiz_file = $self->backend->write_temp_file($quiz_content, $quiz_filename);

        my $quiz_html = EQ::Safeeval::processandrenderquiz( $uid, $iid, $tid, $quiz_file,
            $self->url_for( 'students_submit_quiz',
                'user_id'       => $user_data->{user_id},
                'user_type'     => 'student',
                'instructor_id' => $instructor_id,
                'quiz_id'       => $quiz_id
            ) . ('?browse=' . $self->req->param('browse'))
        );

        # Save quiz finish time
        my $message = "QUIZSTART=[${\time}] STUDENT=[$user_data->{user_id}] INSTRUCTOR=[$instructor_id] QUIZ=[$quiz_id]";
        $self->backend->append_file($instructor_id, 'quizzes.timelog', $message);

        my $metastructrv = eval { EQ::Safeeval::processquizfile( $quiz_file ); };
        if (!$@) {
            $self->stash(quiz_name => $metastructrv->{NAME});
        }

        # Show quiz to student
        $self->render( quiz_html => $quiz_html, is_include_instructor_css => 1 )
    });
}


sub show_quiz_leaderboard {
    my $self = shift;

    $self->_run( sub {
        my $instructor = EQ::Model::Instructors->get_instructor( $self->param('instructor_id') );
        return $self->render( text => "Leaderboard disabled") unless $instructor->{is_enabled_leaderboard};

        my $leaderboard = EQ::Model::Results->get_leaderboard_for_quiz( $self->param('quiz_id') );
        $self->render( leaderboard => $leaderboard );
    });
}

sub show_results {
    my $self = shift;

    $self->_run( sub {
        my $student_results = EQ::Model::Results->get_results_for_student( $self->user_data('user_id') );
        $self->render( student_results => $student_results );
    });
}

# Get quiz answer from student
sub submit_quiz {
    my $self = shift;

    $self->_run( sub {
        my $instructor_id = $self->param('instructor_id');
        my $quiz_id = $self->param('quiz_id');

        return $self->render( text => "Wrong instructor id [$instructor_id]") unless EQ::Model::Instructors->check_id($instructor_id);
        return $self->render( text => "Wrong quiz id [$quiz_id]") unless EQ::Model::Quizzes->check_id($quiz_id);

        return $self->flash( error => "Cannot submit non-started quiz!")->redirect_to('students_show_quizzes')
            unless $quiz_id eq $self->session('quiz_id')
            && $instructor_id eq $self->session('instructor_id');

        $self->session('quiz_id'=> '');


        # Check rup password
        unless ( $self->_check_saved_rup_password($instructor_id) ) {
            return $self->flash( error => 'Wrong password. Quiz results were not saved.' )->redirect_to('students_show_home');
        }

        # Save quiz finish time
        my $user_data = $self->user_data;
        my $finish_time = time();

        if (!$self->_is_email_permitted($instructor_id, $user_data->{user_id})) {
            die 'You are not permitted to view/submit this quiz';
        }

        # Get and save results
        my $results = $self->_get_results_for_submitted_quiz();

        my $browse_mode = $self->req->param('browse');

        if (!$browse_mode) {
            EQ::Model::Results->save_quiz_result(
                quiz_id       => $quiz_id,
                instructor_id => $instructor_id,
                user_id       => $user_data->{user_id},
                user_ip       => $self->_get_ip,
                start_time    => $self->session('start_time'),
                finish_time   => $finish_time,
                results       => $results
            );
        }

        # Show response to user
        my $msg = $browse_mode ? 'Quiz results were NOT saved.' : 'Quiz results were saved.';

        my $instructor = EQ::Model::Instructors->get_instructor($instructor_id);

        if ( $instructor->{is_print_answer} ) {
            $self->flash( notice => $msg );

            my $quiz_filename = "$quiz_id.quiz";
            my $quiz_content =
              $self->backend->slurp_file($instructor_id, $quiz_filename);
            if ($quiz_content =~ m/::FINISH_PAGE::\s*(.*)\s*/) {
                my $finish_page = lc $1;
                if ($finish_page =~ /answers\s*\+\s*results/) {
                    return $self->render( 'students/show_quiz_results', results => $results );
                }
                elsif ($finish_page =~ m/results/) {
                    return $self->render( 'students/show_quiz_results', results => $results, no_answers => 1 );
                }
                else {
                    return $self->redirect_to('students_show_home');
                }
            }
            else {
                return $self->render( 'students/show_quiz_results', results => $results );
            }
        } else {
            my $max_score = @$results;
            my $score     = grep { $_->{is_correct} } @$results;

            $msg .= 'This instructor decided to withhold explanation of answers. ';
            $msg .= "$score out of $max_score questions answered correctly";

            $self->flash( notice => $msg );
            return $self->redirect_to('students_show_home');
        }
    });

}

# Check and save quizz download password
sub qdl_pass_update {
    my $self = shift;

    $self->_run( sub {
        my $instructor_id = $self->param('instructor_id');
        return $self->render( text => "Wrong instructor id [$instructor_id]") unless EQ::Model::Instructors->check_id($instructor_id);

        my $qdl_pass = $self->param('qdl_pass') // '';

        # Quizzes download password update
        $self->um_storage('student')
             ->set( $self->session('user_id'), { "qdl_pass_$instructor_id" => $qdl_pass } );

        $self->flash( notice => 'Password was saved' )->redirect_to('students_show_quizzes');
    });
}

# Check and save records upload password
sub rup_pass_update {
    my $self = shift;

    $self->_run( sub {
        my $quiz_id = $self->session('quiz_id');
        my $redirect_to = $quiz_id ? 'students_show_quiz' : 'students_show_quizzes';

        return $self->flash( is_force_quiz_start => 1 )->redirect_to( $redirect_to, quiz_id => $quiz_id )
            if $self->param('is_force_quiz_start');

        my $instructor_id = $self->param('instructor_id');
        return $self->render( text => "Wrong instructor id [$instructor_id]") unless EQ::Model::Instructors->check_id($instructor_id);

        my $rup_pass = $self->param('rup_pass') // '';

        # Records upload password update
        $self->um_storage('student')->set( $self->session('user_id'), { "rup_pass_$instructor_id" => $rup_pass } );
        $self->flash(  notice => 'Password was saved', )->redirect_to( $redirect_to, quiz_id => $quiz_id );
    });

}

sub set_instructor {
    my $self = shift;

    $self->_run(
        sub {
            my $instructor_id = $self->param('instructor_id');
            return $self->render( text => "Wrong instructor id [$instructor_id]")
              unless EQ::Model::Instructors->check_id($instructor_id);

            my $user_data = $self->user_data;
            $user_data->{instructor_id} = $instructor_id;

            my $user_id = $self->stash('user_id');

            if (!$self->_is_email_permitted($instructor_id, $user_id)) {
                die 'You are not permitted to work with this instructor';
            }

            $self->um_storage->set($user_id, $user_data);

            return $self->redirect_to('students_search', user_id => $user_id);
        }
    );
}

sub search {
    my $self = shift;

    my %vars;
    if ( $self->req->method eq 'POST' && ( my $query = $self->param('query') ) )
    {
        my $backend = $self->backend;

        my $type = $self->param('type');

        if ($type eq 'instructors') {
            my $search = EQ::Model::InstructorSearch->new(backend => $backend);

            $vars{instructors} = $search->search($query);
        }
        else {
            my $search = EQ::Model::QuizSearch->new(backend => $backend);

            $vars{questions} = $search->search($query);
        }
    }

    return $self->render('students/search', %vars);
}

sub browse {
    my $self = shift;

    my %vars;
    if ( $self->req->method eq 'POST' && ( my $query = $self->param('query') ) )
    {
        my $backend = $self->backend;

        my $type = $self->param('type');

        my $search = EQ::Model::QuizSearch->new(backend => $backend);
        $vars{quizzes} = $search->search_quizzes($query);
    }

    return $self->render('students/browse', %vars);
}

sub browse_ajax {
    my $self = shift;

    if (my $query = $self->param('query')) {
        my $backend = $self->backend;

        my $type = $self->param('type');

        my $search = EQ::Model::QuizSearch->new(backend => $backend);

        my $quizzes = $search->search_quizzes($query);
        if (@$quizzes) {
            $quizzes = [
                map {
                    {
                        %$_,
                        browse_url => $self->url_for(
                            'students_show_quiz',
                            instructor_id => $_->{instructor_id},
                            quiz_id       => $_->{quiz_id}
                          )
                          . '?browse=1'
                    }
                  } @$quizzes
            ];
            $self->render(json => {quizzes => $quizzes});
        }
        else {
            $self->render(json => {});
        }
    }
    else {
        $self->render(json => {});
    }
}

#################################### PRIVATE METHODS ####################################

sub _is_email_permitted {
    my $self = shift;
    my ($instructor_id, $user_id) = @_;

    return EQ::Model::StudentAccess->new(backend => $self->backend)
      ->is_email_permitted($instructor_id, $user_id);
}

# Get results from submitted quiz form
sub _get_results_for_submitted_quiz {
    my $self = shift;

    my $form_data = $self->req->params->to_hash();
    my $results = EQ::Quiz::calculate_results($form_data);

    if ($results) {
        return $results;
    } else {
        $self->render( text => 'Error: No questions');
        return;
    }
}

# Check that student has correct instructor's quiz download password
sub _check_saved_qdl_password {
    my ( $self, $instructor_id ) = @_;

    my $instructor = EQ::Model::Instructors->get_instructor($instructor_id);
    return 0 unless $instructor && $instructor->{user_id};
    return 1 unless $instructor->{qdl_password};

    my $saved_password = $self->user_data->{"qdl_pass_$instructor_id"} // '';
    return 1 if $saved_password eq $instructor->{qdl_password};
    return 0;
}

# Check that student has correct instructor's records upload password
sub _check_saved_rup_password {
    my ( $self, $instructor_id ) = @_;

    my $instructor = EQ::Model::Instructors->get_instructor($instructor_id);
    return 0 unless $instructor && $instructor->{user_id};
    return 1 unless $instructor->{rup_password};

    my $saved_password = $self->user_data->{"rup_pass_$instructor_id"} // '';
    return 1 if $saved_password eq $instructor->{rup_password};
    return 0;
}

sub _get_ip {
    my $self = shift;

    my $headers = $self->req->headers;
    return
         $headers->header('x-forwarded-for')
      || $headers->header('x-real-ip')
      || $self->tx->remote_address;
}

1;
