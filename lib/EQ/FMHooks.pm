package EQ::FMHooks;

use v5.14;

use strict;
use warnings;

use JSON;
use Data::Dumper;
use File::Basename qw/fileparse/;
use Text::CSV;
use File::Spec::Functions;
use Digest::MD5 qw/md5_hex/;
use EQ::Safeeval;

# Show quiz to instructor (just to recheck that quiz is working)
sub show_quiz {
    my ( $c, $filepath, $fh ) = @_;
    my ($fname) = fileparse($filepath);

    my $iid = $c->user_data->{user_id};
    my $uid = $c->user_data->{user_id};
    my $tid = $fname;

    my $submit_url = $c->url_for(
        'instructors_try_submit_quiz',
        'user_id'       => $uid,
        'user_type'     => 'intructor'
    );

    my $quiz_html = EQ::Safeeval::processandrenderquiz( $uid, $iid, $tid, $filepath, $submit_url );

    my $html = $c->render(
        partial   => 1,
        quiz_html => $quiz_html,
        template  => 'instructors/show_quiz',
        is_include_instructor_css => 1
    );

    return $html;
}

# Show content of CSV files as HTML table
sub show_csv_variable {
    my ( $c, $filepath, $fh ) = @_;
    my ($fname) = fileparse($filepath);

    my $backend = $c->backend;

    my $user_id = $c->session("user_id");

    my $csv  = Text::CSV->new( { binary => 1 } ) or die "Cannot use CSV: " . Text::CSV->error_diag();
    my $rows = $csv->getline_all($fh);

    my $hrow= shift(@$rows);

    foreach my $row (@$rows) {
        if ($fname =~ m/grades-/) {
            unshift @$row, '';
        }
        else {
            my (undef, $finish_time, $quiz_id, $student_id, $student_name) = @$row;
            my $file_name = md5_hex("${quiz_id}.${student_id}.${finish_time}") . ".result";
            my $file_path = '';
            if ($backend->file_exists($user_id, $file_name)) {
                my $content = $backend->slurp_file($user_id, $file_name);
                $file_path = $backend->write_temp_file($content, $file_name);
            }
            unshift @$row, $file_path;

            splice(@$row, 4, 2, "$student_id - $student_name");
        }
    }

    my $html = $c->render(
        partial  => 1,
        file     => $fname,
        template => 'instructors/show_csv_variable',
        rows     => $rows,
        hrow     => $hrow,
    );

    return $html;
}

# Show content of CSV files as HTML table
sub show_csv_fixed {
    my ( $c, $filepath, $fh ) = @_;
    my ($fname) = fileparse($filepath);

    my $user_id = $c->session("user_id");
    my $backend = $c->backend;

    my $csv  = Text::CSV->new( { binary => 1 } ) or die "Cannot use CSV: " . Text::CSV->error_diag();
    my $rows = $csv->getline_all($fh);

    foreach my $row (@$rows) {
        my ($result_id, $start_time, $finish_time, $quiz_id, $student_id, $student_name, $student_ip) = @$row;
        my $student_info = $student_id;
        $student_info .= " ($student_ip)" if $student_ip;
        splice(@$row, 4, 3, $student_info);

        $row->[1] = $row->[1] . " / ". scalar localtime($row->[1]);
        $row->[2] = $row->[2] . " / ".scalar localtime($row->[2]);
    }

    my $html = $c->render(
        partial  => 1,
        file     => $fname,
        template => 'instructors/show_csv_fixed',
        rows     => $rows,
    );

    return $html;
}


# Show timelog with links to results file
sub show_timelog {
    my ( $c, $filepath, $fh ) = @_;
    my ($fname) = fileparse($filepath);

    my $user_id = $c->session("user_id");

    my @rows;
    while (my $line = <$fh>) {
        my $row = { text => $line };
        if ($line =~ /^QUIZFINISH=\[(\d+)\] STUDENT=\[([^\]]+)\] INSTRUCTOR=\[[^\]]+\] QUIZ=\[([^\]]+)\] RESULT=\[([^\]]+)\]/ ) {
            $row->{result_id} = $4;
        }
        push @rows, $row;
    }

    my $html = $c->render(
        partial  => 1,
        file     => $fname,
        template => 'instructors/show_timelog',
        rows     => \@rows,
    );

    return $html;
}

# rename it from -deleted back to whatever it was
sub undelete_file {
    my ( $c, $filepath, $fh ) = @_;
    my ($basefname) = fileparse($filepath);

    my ($newfname) = $basefname;
    $newfname =~ s/\-deleted$//;

    my $backend = $c->backend;

    my $uid = $c->user_data->{user_id};
    $backend->rename_file($uid, $basefname, $newfname);

    my $site_url = $c->config->{eq}{site_url};
    return "\n<p>undeleted '$basefname'.  Returning to the file manager now.</p>\n<meta http-equiv=\"refresh\" content=\"1;URL=${site_url}/fm\">\n";

    ## how do I get back to the directory view???

    return 0;
}

1;
