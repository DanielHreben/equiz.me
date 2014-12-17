package EQ::Controller::Instructors;

use v5.14;
use Mojo::Base 'Mojolicious::Controller';
use JSON;
use strict;
use warnings;
use Storable;
use File::Slurp qw/read_file/;
use File::Spec::Functions;
use File::Copy;
use File::Compare;
use File::Temp;
use Try::Tiny;
use Text::CSV;
use HTTP::Tiny;
use Digest::MD5 ();

use EQ::Plugin::FileManager::Model::Bucket;
use EQ::Quiz;
use EQ::Model::Students;
use EQ::Model::QuizSearch;


sub _run {
    my ($self, $cb) = @_;

    try {
      $cb->();
    }
    catch {
      $self->flash('error' => $_ )->redirect_to('instructors_show_home');
    };
}

sub show_home {
    my $self = shift;
    $self->render();
}

sub show_full_results {
    my $self = shift;

    $self->_run( sub {
        my $result_id = $self->param('result_id');
        my $result = EQ::Model::Results->get_result($result_id);

        $self->render(
            template    => 'instructors/show_quiz_results',
            results     => $result->{full_result},
            description => "$result->{quiz_id}  - $result->{student_id}"

        );
    });
}


my $weird="";  ## unelegant!

sub copy_deploy_files_form {
    my $self = shift;

    my $source_dir = $self->config("default_files_dir");

    unless ($source_dir) {
        my $home = Mojo::Home->new()->detect('EQ');
        $source_dir = "$home/deploy/";
    }

    opendir( my $dh, $source_dir ) || die "Can't opendir $source_dir: $!";
    my @directories = grep { !/^\./ && -d "$source_dir/$_" } readdir($dh);
    closedir $dh;

    my $tree = [map {{directory => $_, files => []}} @directories];

    foreach my $leave (@$tree) {
        my $directory = $leave->{directory};

        opendir( my $dh, "$source_dir/$directory" ) || die "Can't opendir $source_dir/$directory: $!";
        my @files = grep { !/^\./ && -f "$source_dir/$directory/$_" } readdir($dh);
        closedir $dh;

        push @{$leave->{files}}, @files;
    }

    return $self->render('instructors/copy_deploy_files_form', tree => $tree);
}

sub copy_deploy_files {
  my $self = shift;

  my $source_dir = $self->config("default_files_dir");

  unless ($source_dir) {
    my $home = Mojo::Home->new()->detect('EQ');
    $source_dir = "$home/deploy/";
  }

  my @files = $self->param('file');

  if (@files) {
      my $backend = $self->backend;
      foreach my $file (@files) {
          next unless -f "$source_dir/$file";

          next unless $self->copy_file($self->session("user_id"), "$source_dir/$file");
      }

      $self->flash( error =>"Files were copied successfully" );
  }
  else {
      $self->flash( error =>"Nothing to copy" );
  }

  $self->redirect_to('file_manager_files');
}

sub copy_files {
  my ($self, $instructor_id, $source_dir) = @_;

  foreach my $file (glob("$source_dir/*")) {
    ($file =~ /\~$/) and next; # omit backup files
    ($file =~ /^\#.*\#$/) and next; # omit temporary saved emacs files

    #$self->app->log->debug("copy($file, $user_dir)");

    (my $basename= $file) =~ s/.*\///;

    my $backend = $self->backend;

    return if $backend->file_exists($instructor_id, $basename);

    $backend->write_file_from_path($instructor_id, $basename, $file);
  }

  return 1;
}

sub copy_file {
    my $self = shift;
    my ($instructor_id, $file) = @_;

    (my $basename= $file) =~ s/.*\///;

    my $backend = $self->backend;

    return if $backend->file_exists($instructor_id, $basename);

    $backend->write_file_from_path($instructor_id, $basename, $file);

    return 1;
}

################

sub rm_all_files {
  my $self = shift;

  my $source_dir = $self->config("default_files_dir");

  unless ($source_dir) {
      my $home = Mojo::Home->new()->detect('EQ');
      $source_dir = "$home/deploy/";
  }

  opendir(my $dh, $source_dir) || die "Can't opendir $source_dir: $!";
  my @directories = grep { !/^\./ && -d "$source_dir/$_" } readdir($dh);
  closedir $dh;

  my $has_errors;
  foreach my $directory (@directories) {
      if( !$self->rm_files($self->session("user_id"), "$source_dir/$directory") ) {
          $has_errors = $!;
      }
  }

  if ($has_errors) {
      $self->flash( error =>"Removal failed: $!" );
  }
  else {
      $self->flash( error =>"Files were removed successfully" );
  }

  $self->redirect_to('file_manager_files');
}

sub rm_files {
  my ($self, $instructor_id, $source_dir) = @_;

  my $backend = $self->backend;

  foreach my $file (glob("$source_dir/*")) {
    ($file =~ /\~$/) and next; # omit backup files
    ($file =~ /^\#.*\#$/) and next; # omit temporary saved emacs files

    #$self->app->log->debug("copy($file, $user_dir)");

    (my $basename = $file) =~ s/.*\///;

    if ($backend->file_exists($instructor_id, $basename)) {
        my $content = $backend->slurp_file($instructor_id, $basename);
        my $fulldestname = $backend->write_temp_file($content);
        if (compare($fulldestname, $file) == 0) {
            ## this is just a copy, so delete it
            $backend->delete_file($instructor_id, $basename);
        }
    }
  }

  return 1;
}


sub instructors_make_grades {
    my ($self) = @_;

    my $user_id = $self->session('user_id');

    my $retstr = makegrades($self, $user_id);

    $self->flash(notice => "$retstr");
    $self->redirect_to('file_manager_files');

}

sub makegrades {
    my $self = shift;
    my ($user_id) = @_;

  my $backend = $self->backend;

  my @resultscsvformat= qw(time-start time-end quizname username);
  my $usercolumn= 4; ## the results columns are always from the rear and always 0 or 1.  so they are inferred

  my $results;  ## will contain everything

  my @files = $backend->list_files($user_id, match => qr/results\.csv$/);

  my @resultsfilenames;
  foreach my $rfn (sort(@files)) {
    my %first; my %best; my %all;

    my $RES = $backend->slurp_file($user_id, $rfn);

    (my $namequiz= $rfn) =~ s/^(.*)\.20.*/$1/;  ## just grab the name of the quiz itself
    $namequiz =~ s/.*\///;
    $namequiz = "Q$namequiz";
    push(@resultsfilenames, $namequiz);

    my $maxn=0;

    foreach (split /\n/, $RES) {
        chomp;
        (/[0-9]/) or next;
        my @flds  = split(/\,/);
        my $score = 0;
        my $curn  = 0;
        for (my $fn = $#flds; $fn > $usercolumn; --$fn) {
            (($flds[$fn] ne "0") && ($flds[$fn] ne "1")) && ($flds[$fn] ne "") and last;
            $score += $flds[$fn];
            ++$curn;
        }
        my $uname = $flds[$usercolumn];

        (defined($first{$uname})) or $first{$uname} = $score;
        $all{$uname} .= " $score";
        $best{$uname} =
            (!(defined($best{$uname})))          ? $score
          : ($best{$flds[$usercolumn]} < $score) ? $score
          :                                        $best{$flds[$usercolumn]};
        $results->{unames}->{$uname} = 1;
    }

    $results->{first}->{$namequiz} = \%first;
    $results->{best}->{$namequiz}  = \%best;
    $results->{all}->{$namequiz}   = \%all;
    $results->{maxn}->{$namequiz}  = $maxn;
  }

  my @usernames= sort keys %{$results->{unames}}; ## all users;

  $self->_mergeresultstructure($backend, $user_id, "grades-first.csv", $results->{first}, \@usernames, \@resultsfilenames);
  $self->_mergeresultstructure($backend, $user_id, "grades-best.csv", $results->{best}, \@usernames, \@resultsfilenames);
  $self->_mergeresultstructure($backend, $user_id, "grades-all.csv", $results->{all}, \@usernames, \@resultsfilenames);

  return "created grades-all.csv, grades-best.csv, and grades-first.csv from ". join(" ", @resultsfilenames);
}

sub _mergeresultstructure {
    my $self = shift;
    my ($backend, $user_id, $ofn, $results, $users, $quizzes) = @_;

    my $output = '';

    $output .= "student," . join(",", @{$quizzes}) . "\n";
    foreach my $student (@{$users}) {
        $output .= "$student";
        foreach my $quiz (@{$quizzes}) {
            my $a = ($results->{$quiz}->{$student} || "NA");
            $a =~ s/^\;//;
            $output .= ",$a";
        }
        $output .= "\n";
    }

    $backend->overwrite_file($user_id, $ofn, $output);
}

sub try_submit_quiz {
    my $self = shift;

    $self->_run( sub {
        my $form_data = $self->req->params->to_hash();
        my $results = EQ::Quiz::calculate_results($form_data);

        if ($results) {
            # We Render student template here to fully emulate students view
            return $self->render( 'students/show_quiz_results',
              results => $results,
              layout  => 'instructor'
            );
        } else {
            $self->render( text => 'Error: No questions');
        }
    });
}

sub remind_students_form {
    my $self = shift;

    return $self->render( 'instructors/remind_students_form');
}

sub remind_students_submit {
    my $self = shift;

    my $type = $self->param('type');

    my $content;
    if ($type eq 'upload') {
        my $upload = $self->param('f');

        if (!$upload || !$upload->can('filename') || !$upload->filename) {
            return $self->render('instructors/remind_students_form',
                error => 'File required');
        }

        my $filename = $upload->filename;

        $content = $upload->slurp;
    }
    else {
        my $url = $self->param('url');

        if (!$url) {
            return $self->render('instructors/remind_students_form',
                error => 'URL required');
        }

        my $response = HTTP::Tiny->new->get($url);

        return $self->render('instructors/remind_students_form',
            error => 'Download failed') unless $response->{success};

        $content = $response->{content};
    }

    if ($content !~ m/id,/) {
        return $self->render('instructors/remind_students_form',
            error => 'Not a CSV file');
    }

    my $session = '';
    $session .= int(rand(10)) for 1 .. 8;

    open my $fh, '>', "/tmp/eq-session-$session";
    print $fh $content;
    close $fh;

    $self->session(remind_students => $session);

    $self->redirect_to('instructors_remind_students',
        user_type => 'instructor');
}

sub remind_students {
    my $self = shift;

    my @students = $self->_get_remind_students_list;
    return $self->render_not_found unless @students;

    my $registered     = [];
    my $not_registered = [];

    foreach my $entry (@students) {
        my $student = EQ::Model::Students->get_student($entry->{email});

        if ($student) {
            push @$registered, $student;

            my $quizzes = EQ::Model::Quizzes->get_quizzes_for_instructor($self->session('user_id'));

            my $results =
              EQ::Model::Results->get_results_for_student($student->{email});
            my %results;
            foreach my $result (@$results) {
                $results{$result->{quiz_id}}++;
            }
            foreach my $quiz (@$quizzes) {
                if (exists $results{$quiz->{quiz_id}}) {
                    $quiz->{is_submitted} = 1;
                }
            }

            $student->{quizzes} = [map {$_->{name},} grep { !$_->{is_submitted} } @$quizzes];
        }
        else {
            push @$not_registered, $entry;
        }
    }

    if ($self->req->method eq 'POST') {
        if ($self->param('type') =~ m/register/) {
            my $url = $self->url_for('user_create_form', user_type => 'student');
            $url->query(instructor_id => $self->session('user_id'));

            foreach my $email ($self->param('email')) {
                $self->_send_email_to_register($email, $url->to_abs);
            }
        }
        elsif ($self->param('type') =~ m/quiz/) {
            foreach my $email ($self->param('email')) {
                my ($student) = grep { $_->{email} eq $email } @$registered;

                if ($student && !$student->{unsubscribed}) {
                    $self->_send_email_to_finish_quizzes($email, $student->{quizzes});
                }
            }
        }

        $self->stash(message => 'Students were notified');
    }

    return $self->render(
        'instructors/remind_students',
        registered     => $registered,
        not_registered => $not_registered
    );
}

sub search {
    my $self = shift;

    my %vars;
    if ( $self->req->method eq 'POST' && ( my $query = $self->param('query') ) )
    {
        my $backend = $self->backend;

        my $search = EQ::Model::QuizSearch->new(backend => $backend);

        $vars{matches} = $search->search($query);
    }

    return $self->render('instructors/search', %vars);
}

sub quiz_designer {
    my $self = shift;

    my @global_fields_order = (qw/NAME EMAIL INSTRUCTOR LICENSE SHARING EQVERSION/);

    my $global_fields = [
        { name => 'NAME',       label => 'Name', class => 'required', placeholder => 'e.g., My NPV Quiz' },
        { name => 'EMAIL',      label => 'Email', class => 'required', placeholder => 'e.g., me\@my.com' },
        { name => 'INSTRUCTOR', label => 'Instructor', class => 'required', placeholder => 'e.g., prof me my' },
        {
            name  => 'LICENSE',
            label => 'License',
            value => 'Equiz Standard License',
            variants =>
              [ 'Equiz Standard License', 'Write My Own (editable)' ]
        },
        {
            name     => 'SHARING',
            label    => 'Sharing',
            value => 'Visible to Other Equiz Instructors',
            variants => [
                'Visible to Other Equiz Instructors',
                'Private (Not Visible) to Other Equiz Instructors',
            ]
        },
        {
            name     => 'FINISH_PAGE',
            label    => 'Page shown after quiz submission',
            value => 'answers+results',
            variants => [
                'answers+results',
                'results',
                'nothing',
            ]
        },
        { name => 'EQVERSION', label => 'EQ Version', value => '1.0', type => 'hidden' },
    ];

    my $sample_question = [
        {
            name => 'N',
            label => 'Question Name',
            class => 'required',
	    placeholder => 'e.g., My NPV Question'
        },
        {
            name => 'I',
            label => 'Initializer',
            type => 'textarea',
            class => 'required resizable',
	    placeholder => 'e.g., $x=rseq(10,20); $ANS=$x+1'
        },
        {
            name => 'Q',
            label => 'Question Text',
            type => 'textarea',
            class => 'required resizable',
	    placeholder => 'e.g., What is {$x}+1?
                When in {}, it means evaluate.'
        },
        {
            name => 'S',
            label => 'Numeric Answer',
            class => 'required',
	    placeholder => 'e.g., $ANS . ($ANS is the default, too)'
        },
        {
            name => 'P',
            label => 'Precision',
	    placeholder => 'e.g., 0.001 .  leave empty for "smart".',
        },
        {
            name => 'L',
            label => 'Answer Explanation',
            type => 'textarea',
            class => 'required resizable',
	    placeholder => 'e.g., The answer to {$x}+1 is {$ANS}.'
        },
        {
            name => 'T',
            label => 'Recommended Time',
	    placeholder => 'e.g., 1'
        },
        {
            name => 'D',
            label => 'Difficulty Level',
	    placeholder => 'e.g., hard'
        },
    ];

    if (my $filename = $self->param('f')) {
        my $instructor_id = $self->session("user_id");

        my $backend = $self->backend;

        return $self->render_not_found unless $backend->file_exists($instructor_id, $filename);

        my $content = $backend->slurp_file($instructor_id, $filename);

        my ($fh, $temp_filename) = File::Temp::tempfile();
        $content = Encode::encode('UTF-8', $content);
        print $fh $content;
        close $fh;

        my $metastructrv = eval { EQ::Safeeval::processquizfile( $temp_filename ); };

        if ($@) {
            my $e = $@;

            $e =~ s{^.*?:\d+:\s*}{};
            $e =~ s{(?:\n\r|\n|\r)}{}g;
            $e =~ s{\s+at [\S]+ line.*}{}ms;

            die "$e\n";
        }
        else {
            delete $metastructrv->{randgenerated};
            my $questions = [];
            my $raw_questions = delete $metastructrv->{ALLQUESTIONS};

            my $my_global_fields = [];
            foreach my $key (keys %$metastructrv) {
                my $value = $metastructrv->{$key};
                $value = '' unless defined $value;
                $value =~ s{^\s*}{};
                $value =~ s{\s*$}{};

                if (my ($field) = grep {$_->{name} eq $key} @$global_fields) {
                    $field->{value} = $value;
                    push @$my_global_fields, $field;

                    if (exists $field->{variants}) {
                        push @{$field->{variants}}, $value
                          unless grep { $_ eq $value } @{$field->{variants}};
                    }
                }
                else {
                    push @$my_global_fields, {name => $key, type => 'hidden', value => $value};
                }
            }

            my $my_global_fields_sorted = [];
            foreach my $key (reverse @global_fields_order) {
                if (my ($field) = grep { $_->{name} eq $key } @$my_global_fields) {
                    unshift @$my_global_fields_sorted, $field;
                }
            }
            foreach my $field (@$my_global_fields) {
                if (!grep { $_->{name} eq $field->{name} } @$my_global_fields_sorted) {
                    push @$my_global_fields_sorted, $field;
                }
            }

            foreach my $raw_question (@$raw_questions) {
                if ($raw_question->{MSG}) {
                    push @$questions,
                      {
                        fields => [
                            {
                                name  => 'M',
                                type  => 'textarea',
                                value => $raw_question->{MSG}
                            }
                        ]
                      };
                    next;
                }

                next unless $raw_question->{N};

                my $question = {fields => Storable::dclone($sample_question)};
                foreach my $field (@{$question->{fields}}) {
                    $field->{value} =
                      exists $raw_question->{$field->{name} . '_'}
                      ? $raw_question->{$field->{name} . '_'}
                      : $raw_question->{$field->{name}};

                    if (defined $field->{value}) {
                        $field->{value} =~ s{^\s*}{};
                        $field->{value} =~ s{\s*$}{};

                        if ($field->{type} && $field->{type} eq 'textarea') {
                            my $height = 1;
                            $height = length($field->{value}) / 40;

                            $field->{rows} = int($height > 2 ? $height : 2);
                        }
                    }
                    else {
                        $field->{value} = '';
                    }
                }

                if ($raw_question->{CNT} && $raw_question->{C}) {
                    $question->{is_multi} = 1;
                    push @{$question->{fields}},
                      {
                        name  => 'C',
                        label => 'Choices',
                        value => $raw_question->{C},
                        class => 'required'
                      };

                    $question->{fields} = [grep { $_->{name} ne 'P' } @{$question->{fields}}];
                    #push @$question, {name => 'CNT', label => 'Cnt', value => $raw_question->{CNT}};
                }

                push @$questions, $question;
            }

            $self->stash(
                global_fields   => $my_global_fields_sorted,
                sample_question => {fields => $sample_question},
                questions       => $questions
            );
        }
    }
    else {
        $self->stash(
            global_fields   => $global_fields,
            sample_question => {fields => $sample_question},
            questions       => []
        );
    }
}

sub eval_quiz {
    my $self = shift;

    my $content = $self->param('content');

    my $quiz = <<"EOF";
::NAME:: Sandbox

::INSTRUCTOR:: sandbox

::EQVERSION:: 1.3

::START::

$content

::END::
EOF

    my ($fh, $filename) = File::Temp::tempfile();
    print $fh $quiz;
    close $fh;

    my $metastructrv = eval { EQ::Safeeval::processquizfile( $filename ); };

    my $error;
    if ($@) {
        $error = $@;
    }

    return $self->render(json => {error => $error, result => $metastructrv->{ALLQUESTIONS}->[0]});
}

sub _get_remind_students_list {
    my $self = shift;

    my $session = $self->session('remind_students');
    return unless $session =~ m/^\d+$/;

    return $self->_parse_csv("/tmp/eq-session-$session");
}

sub _parse_csv {
    my $self = shift;
    my ($file) = @_;

    open my $fh, '<', $file or return;

    my $csv = Text::CSV->new() or die "Cannot use CSV: " . Text::CSV->error_diag();

    my $fields = $csv->getline($fh);

    my @students;
    while (my $row = $csv->getline($fh)) {
        my $student;
        foreach my $field (@$fields) {
            my $value = shift @$row;

            for ($value) { s/^\s*//g; s/\s*$//g }

            $student->{$field} = $value;
        }
        push @students, $student;
    }
    $csv->eof or $csv->error_diag();

    return @students;
}

sub _send_email_to_register {
    my $self = shift;
    my ($email, $url) = @_;

    $self->mail(
        to      => $email,
        subject => "A reminder to register",
        data    => <<"EOF",
This is a reminder to register for quiz. Please click the following link:

    $url

EOF
    );
}

sub _send_email_to_finish_quizzes {
    my $self = shift;
    my ($email, $quizzes) = @_;

    my $unsubscribe_url = $self->url_for(
        'user_unsubscribe',
        user_type => 'student',
        user_id   => $email
    )->to_abs;

    $self->mail(
        to      => $email,
        subject => "A reminder to finish quizzes",
        data    => <<"EOF",
This is a reminder to finish the following quizzes: @{[join ', ', @$quizzes]}.

--
If you want to unsubscribe from the email notifications, click the following link:
$unsubscribe_url
EOF
    );
}
1;
