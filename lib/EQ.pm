package EQ;

use v5.14;

use strict;
use warnings;

use Mojo::Base 'Mojolicious';
use Validate::Tiny qw/is_required is_like is_in/;
use File::Path qw/make_path/;
use File::Copy qw/copy/;
use File::Spec::Functions qw/catdir rel2abs/;
use File::Slurp qw/read_file/;
use Locale::Country;
use File::Basename qw/dirname/;
use Hash::Storage;
use Digest::MD5 qw/md5_hex/;
use Digest::SHA2;
use Data::Dumper;
use Mojo::Util qw/url_escape/;

use Mojo::Home;
use Mojo::ByteStream qw/b/;

use EQ::Safeeval;
use EQ::FMHooks;
use EQ::Model::StudentAccess;
use EQ::Controller::Instructors;

use EQ::Model;

sub startup {
    my $self = shift;

    $self->sessions->default_expiration(3600*24);
    $self->secrets(['This secret protect sessions!!!']);

    # Load Plugins
    my $config = $self->plugin( 'Config', { file => 'etc/eq.conf' } );

    EQ::Model->init($config->{model});

    #$self->plugin( 'Recaptcha', $config->{recaptcha} );
    $self->plugin( 'Mail', $config->{mail} );
    $self->plugin( 'Gravatar', $config->{gravatar} || {} );
    $self->plugin( 'CSRFDefender' );

    EQ::Plugin::FileManager::Model::Bucket->setup(%{$config->{file_manager}});
    $self->plugin( 'EQ::Plugin::FileManager', $self->_get_fm_schema($config) );

    my ($instructor, $student) = $self->plugin(
        'EQ::Plugin::UserManager', [
            $self->_get_instructor_schema($config),
            $self->_get_student_schema($config),
        ]
    );

    $self->_register_helpers($config);

    # Setup guest routes
    my $r = $self->routes;
    $r->namespaces(['EQ::Controller']);
    # $r->get( '/' => sub { shift->redirect_to('auth_create_form', user_type => 'student') } );
    $r->get( '/' => sub { shift->redirect_to('static/index.html') } );

    # Setup instructors routes
    $instructor->get('/home')->to('instructors#show_home')->name('instructors_show_home');
    $instructor->get('/full_results/:result_id')->to('instructors#show_full_results')->name('instructors_show_full_results');
    $instructor->post('/try_submit_quiz')->to('instructors#try_submit_quiz')->name('instructors_try_submit_quiz');
    $instructor->get('/copy_deploy_files')->to('instructors#copy_deploy_files_form')->name('instructors_copy_deploy_files_form');
    $instructor->post('/copy_deploy_files')->to('instructors#copy_deploy_files')->name('instructors_copy_deploy_files');
    $instructor->post('/rm_all_files')->to('instructors#rm_all_files')->name('instructors_rm_all_files');
    $instructor->post('/instructors_make_grades')->to('instructors#instructors_make_grades')->name('instructors_make_grades');

    $instructor->get('/remind_students_form')
      ->to('instructors#remind_students_form')
      ->name('instructors_remind_students_form');
    $instructor->post('/remind_students_submit')
      ->to('instructors#remind_students_submit')
      ->name('instructors_remind_students_form');
    $instructor->any('/remind_students')->to('instructors#remind_students')
      ->name('instructors_remind_students');

    $instructor->any('/search')->to('instructors#search')
      ->name('instructors_search');

    $instructor->any('/quiz_designer')->to('instructors#quiz_designer')
      ->name('instructors_quiz_designer');
    $instructor->any('/eval_quiz')->to('instructors#eval_quiz')
      ->name('instructors_eval_quiz');
    $instructor->any('/toggle_quiz')->to('instructors#toggle_quiz')
      ->name('instructors_toggle_quiz');

    # Setup students routes
    $student->get('/home')->to('students#show_home')->name('students_show_home');
    $student->get('/results')->to('students#show_results')->name('students_show_results');

    $student->get('/instructors')->to('students#show_instructors')->name('students_show_instructors');
    $student->get('/instructors/#instructor_id/quizzes')->to('students#show_quizzes')->name('students_show_quizzes');
    $student->get('/instructors/#instructor_id/quiz/#quiz_id')->to('students#show_quiz')->name('students_show_quiz');
    $student->post('/instructors/#instructor_id/quiz/#quiz_id')->to('students#submit_quiz')->name('students_submit_quiz');
    $student->get('/instructors/#instructor_id/quiz_leaderboard/#quiz_id')->to('students#show_quiz_leaderboard')->name('students_show_quiz_leaderboard');


    # Quzzes download password (qdl_pass)
    $student->get('/instructors/#instructor_id/qdl_pass_update')->to('students#qdl_pass_update_form')->name('students_qdl_pass_update_form');
    $student->post('/instructors/#instructor_id/qdl_pass_update')->to('students#qdl_pass_update')->name('students_qdl_pass_update');

    # Records upload password (rup_pass)
    $student->get('/instructors/#instructor_id/rup_pass_update')->to('students#rup_pass_update_form')->name('students_rup_pass_update_form');
    $student->post('/instructors/#instructor_id/rup_pass_update')->to('students#rup_pass_update')->name('students_rup_pass_update');

    # Show full results
    $student->get('/full_results/:result_id')->to('students#show_full_results')->name('students_show_full_results');

    $student->any('/set_instructor')->to('students#set_instructor')->name('students_set_instructor');
    $student->any('/search')->to('students#search')->name('students_search');
    $student->any('/browse')->to('students#browse')->name('students_browse');
    $student->any('/browse_ajax')->to('students#browse_ajax')->name('students_browse_ajax');
}

sub dispatch {
    my $self = shift;
    my ($c) = @_;

    my $is_old_browser = 0;

    my $user_agent = $c->tx->req->headers->header('user-agent');

    if ($user_agent =~ m/MSIE\s+(\d+)/i) {
        $is_old_browser = 1 if $1 <= 6;
    }

    $c->stash(old_browser => $is_old_browser);

    return $self->SUPER::dispatch(@_);
}


################################################################################################################################
### now comes the file manager init

sub _get_fm_schema {
    my ($self, $config) = @_;
    return  {
        layout         => 'instructor',
        access_checker => sub {
            my $c = shift;
            if ( $c->session('user_id') && $c->session('user_type') eq 'instructor' ) {
                if ( my $timeout = $c->um_config('instructor')->{session_expiration} ) {
                    if ($c->session('lifetime') < time ) {
                        $c->redirect_to('auth_create_form', user_type => 'instructor');
                        return 0;
                    }
                }

                $c->stash( user_id => $c->session('user_id'), user_type => $c->session('user_type') );
                return 1;
            } else {
                $c->redirect_to('auth_create_form', user_type => 'instructor');
                return 0;
            }
        },
        user     => sub { shift->user_data->{user_id} },
        root_dir => $config->{file_manager}{root_dir},
        hide     => qr/.result$/,
        hooks    => [
            {
                name => 'Preview Public Quiz',
                cb   => \&EQ::FMHooks::show_quiz,
                css => "background-color:orange",
                filter => qr/^[\w\-.]+\.(?:quiz)$/
            },
            {
                name => 'Preview Testbank',
                cb   => \&EQ::FMHooks::show_quiz,
                filter => qr/^[\w\-.]+\.(?:testbank)$/
            },
            {
                name => 'Table',
                cb   => \&EQ::FMHooks::show_csv_fixed,
                filter => qr/^[\w\-.]+\.results\.csv$/
            },
            {
                name => 'Table',
                cb   => \&EQ::FMHooks::show_csv_variable,
                filter => qr/^grades[\w\-.]+\.csv$/
            },
            {
                name => 'View Log',
                cb   => \&EQ::FMHooks::show_timelog,
                filter => qr/^[\w\-.]+\.timelog/
            },
            {
        name => "Undelete",
        cb => \&EQ::FMHooks::undelete_file,
        css => "text-decoration:strike-through; background-color:gray",
                filter => qr/\-deleted$/
            },

        ],
    };
}


################################################################################################################################
### now comes the user manager init

my %fieldis = (
           'email' => {
               name  => 'email',
               label => 'Email <span class="req">*</span>',
               tag_options => [ title => 'Your email is your user id', placeholder => 'e.g., jdoe+econ101s01@learn.edu', style => 'width:40ex' ],
#               check => [ is_required(), is_like( qr/^.+\@.+\..+$/, 'must be a pattern like a@b.c' ) ],
#http://www.regular-expressions.info/email.html
               check => [ is_required(), is_like( qr/^[a-zA-Z0-9][a-zA-Z0-9\%\.\_\+\-]+\@[a-zA-Z0-9\.\-]+\.[a-zA-Z]+$/,
                                  'must be a pattern like a@b.c' ) ],
               ## warning --- the email is written into the filesystem as user id.  so, it must be safe
               ## worries are '>' , '<', "|", '..', '/', ...
              },
           'user_id' => {
                 name  => 'user_id',
                 label => 'Repeat Email <span class="req">*</span>',
                 tag_options  => [ title => "Repeat your email exactly", placeholder => 'e.g., jdoe+econ101s01@learn.edu', style => 'width:40ex' ],
                 check => [ is_required(), sub {
                      my ($user_id, $params) = @_;
                      return "Emails do no coincide" unless $user_id eq $params->{email};
                      return;
                    }]
                },
           'password' => {
                  name  => 'password',
                  label => 'Password <span class="req">*</span>',
                  type  => 'password',
                  tag_options  => [ title => "Minimum password length is 6 characters and use of 1 digit", placeholder => "e.g., abcde1" ],
                  hint  => "Min: 6 characters, 1 non-letter",
                  check => [
                    is_required(), is_like( qr/^(?=.*(\d|\W)).{6,20}$/, "Minimum password length 6 characters; ; &ge;1 digit") ],
                 },
           'password2' => {
                   name  => 'password2',
                   label => 'Repeat Password <span class="req">*</span>',
                   type  => 'password',
                   tag_options  => [ title => "same as above", placeholder => "e.g., abcde1" ],
                   hint  => "again",
                  },
           'first_name' => {
                name  => 'first_name',
                label => 'First name <span class="req">*</span>',
                tag_options  => [ title => "Public. Required", placeholder => 'e.g., john' ],
                check => [
                      is_required(),
                      is_like( qr/^[\w\-\.]+$/, 'can contain only letters, periods, and dashes' )
                     ],
                   },
           'last_name' => {
                   name  => 'last_name',
                   label => 'Last name <span class="req">*</span>',
                   tag_options  => [ title => "Public. Required", placeholder => 'e.g., doe' ],
                   check => [ is_required(), is_like( qr/^[\w\-\.]+$/, 'can contain only letters, periods, and dashes' ) ],
                  },

           'ssn' => {
             name  => 'ssn',
             label => '4 Memorable Digits <span class="req">*</span>',
             check => [ is_required(), is_like( qr/^\d{4}$/, 'must be 4 digits long' ) ],
             tag_options => [  style => 'width:5ex', 'maxlength' => 4,  title => "Private. Required.  Possible Future Confirm Authorization.", placeholder => '9876' ],
            },
           'gender' => {
                name  => 'gender',
                label => 'Gender',
                check => [ is_required(), is_in( [ 'u', 'm', 'f' ] ) ],
                type  => 'select',
                tag_options => [ [ ['Unspec or Unsure' => 'u' ], [ 'Male' => 'm' ], [ 'Female' => 'f' ] ] ],
               },
           'phone_number' => {
                  name  => 'phone_number',
                  label => 'Phone number',
                  check => [ is_like( qr/^[\d()\-+]{6,20}$/, 'must be 6-20 digits long. also, can contain parens and dashes' ) ],
                  tag_options => [ 'maxlength' => 20, title => "Private  Possible Future Confirm Authorization.", placeholder => 'e.g., 001-310-555-1212' ],
                 },
           'institution' => {
                 name  => 'institution',
                 label => 'Institution <span class="req">+</req>',
                 tag_options => [  style => 'width:40ex', title => "Public. Highly Recommended.  Helps your students find you.", placeholder => 'e.g., Learn University School of Learning' ],
                },

           'street' => {
                name  => 'street',
                label => 'Street Address',
                tag_options => [ style => 'width:40ex', title => "Private", placeholder => 'e.g., 1 Main Street' ],
               },

           'city' => {
              name  => 'city',
              label => 'City',
              check => is_like( qr/^[\w\s.,\-]+$/, 'can contain only digits, letters, spaces, periods, dashes' ),
              tag_options => [ title => "Private", placeholder => 'e.g., Metropolis' ],
             },

           'state' => {
               name  => 'state',
               label => 'State',
               tag_options => [ placeholder => 'e.g., NY' ],
              },

           'postal_code' => {
                 name  => 'postal_code',
                 label => 'Postal Code',
                 check => is_like( qr/^[^\s]+$/, 'can contain only non-spaces' ),
                 tag_options => [ placeholder => 'e.g., 10000-0001' ],
                },
           'country' => {
                 name  => 'country',
                 class => 'searchable',
                 label => 'Country <span class="req">*</span>',
                 type  => 'select',
                 check => [ is_required(), is_like(qr/^[a-z]{2}$/) ],
                 tag_options => sub {
                   my $c = shift;
                   my @select_options = [ "USA" => "us" ];
                   foreach my $country ( sort( all_country_names() ) ) {
                 push @select_options, [ $country => country2code($country) ];
                   }
                   return [ \@select_options, style => 'width:150px' ];
                 },
                },
           'class' => {
               name  => 'class',
               label => 'Course Name  <span class="req">+</span>',
               tag_options => [  style => 'width:40ex', title => "Public.  Highly Recommended.  Helps your students find you.", placeholder => 'e.g., Corporate Finance' ],

              },
           'classcode' => {
               name  => 'classcode',
               label => 'Course Code <span class="req">+</span>',
                   tag_options => [  style => 'width:40ex', title => "Public.  Highly Recommended.  Helps your students find you.", placeholder => 'e.g., Fin101-S01' ],
                  },
           'is_agree_with_usage_condition' =>
              {
               name  => 'is_agree_with_usage_condition',
               label => 'Agree to <a target="_blank" href="/static/legal.html"> Legal Usage </a> Conditions <span class="reg">*</span>',
               type  => 'checkbox',
               check => [ is_required('Agree to proceed'), is_in([1]) ],
              },
           'is_enabled_leaderboard' =>  {
                         name  => 'is_enabled_leaderboard',
                         label => 'Enable student leaderboards',
                         type  => 'checkbox',
                         check => [is_in([1])],
                         default => 1
                        },
           'hr_skip' => { name => 'hr', label => '', type => 'tag', skip_on_reg => 1 },
           'hr' => { name => 'hr', label => '', type => 'tag' },

          );



sub _get_instructor_schema {
    my ($self, $config) = @_;
    return {
        layout        => 'instructor',
        user_type     => 'instructor',
        home_url      => 'instructors_show_home', # url or route name
        captcha       => $config->{user_manager}{captcha},
        email_confirm => $config->{user_manager}{email_confirm},
        admin_confirm => $config->{user_manager}{admin_confirm},
        admin_email   => $config->{user_manager}{admin_email},
        session_expiration => 3600*24,
        plain_auth    => 1,
        site_url      => $config->{user_manager}{site_url},
        password_crypter => sub { $self->_crypt_password(@_) },
        login_labels  => {
            title    => "
<header>
  <table class=\"hdr\">
    <tr>
      <td> <span class='gravatar'> <img src='/static/img/equizavatar.jpg' alt='Gravatar' height='80' width='80' /> </span> &nbsp;&nbsp; </td>
      <td> <span class=\"hdruid\"> Instructors </span>
          <br />&nbsp;<br />
          <span class=\"hdrfid\"> Log In </span> </td>
    </tr>
    <tr> <td colspan=\"2\"> <span class=\"gravatarbottom\">Equiz.Me</span>
           <br />&nbsp;</td>
    </tr>
  </table>
</header>
<hr />",
            user_id  => 'Email',
            password => 'Password',
            submit    => 'Login'
        },
        registration_labels  => {
            title => "
<header>
  <table class=\"hdr\">
    <tr>
      <td> <span class='gravatar'> <img src='/static/img/equizavatar.jpg' alt='Gravatar' height='80' width='80' /> </span> &nbsp;&nbsp; </td>
      <td> <span class=\"hdruid\"> Instructors </span>
          <br />&nbsp;<br />
          <span class=\"hdrfid\"> Registration </span> </td>
    </tr>
    <tr> <td colspan=\"2\"> <span class=\"gravatarbottom\">Equiz.Me</span>
           <br />&nbsp;</td>
    </tr>
  </table>
</header>
<hr />",
        },
        profile_labels  => {
            title => '',
            page_title => 'Instructor Update Settings'
        },
        password_reminder_labels => {
            title  => '<h1>Instructor Remind Password</h1>'
        },
        storage  => EQ::Model::Storages->get_instructors_storage(),
        on_registration => sub {
            my ($c, $user_data) = @_;

            my $source_dir = $self->config("intro_files_dir");
            unless ($source_dir) {
                my $home = Mojo::Home->new()->detect('EQ');
                $source_dir = "$home/deploy/intro";
            }

            EQ::Controller::Instructors::copy_files($c, $user_data->{user_id}, $source_dir);
        },
        fields    => [
              $fieldis{'email'},
              $fieldis{'user_id'},
              $fieldis{'password'},
              $fieldis{'password2'},

              $fieldis{'first_name'},
              $fieldis{'last_name'},
              $fieldis{'ssn'},
              $fieldis{'gender'},
              $fieldis{'phone_number'},

              $fieldis{'hr_skip'},

              {
               name  => 'instructorsite',
               label => 'Instructor Web Site <span class="req">*</span>',
               tag_options => [ style => 'width:40ex', title => 'Public and Shown to Your Students', placeholder => 'e.g. www.learn.edu/~jdoe' ],
              },
              $fieldis{'institution'},
              $fieldis{'street'},
              $fieldis{'city'},
              $fieldis{'state'},
              $fieldis{'postal_code'},
              $fieldis{'country'},

              $fieldis{'hr_skip'},

              $fieldis{'classcode'},
              $fieldis{'class'},
              {
               name  => 'coursesite',
               label => 'Course Web Site <span class="req">*</span>',
               tag_options => [  style => 'width:40ex', title => 'Public and Shown to Your Students', placeholder => 'e.g. www.learn.edu/~jdoe/econ1' ],
              },

              {
               name  => 'areaclass',
               class => 'searchable',
               label => 'Area Classification',
               type => 'select',
               check => [ is_like(qr/^[A-Z]{2}$/) ],
               tag_options => sub {
             my $c = shift;
             my @area_class = (
                       [ "Finance" => "FI" ],
                       [ "Economics" => "EC" ],
                       [ "Business" => "BU" ],
                       [ "Social Science (Other)" => "SS" ],
                       [ "Hard Science (incl. Math)" => "HS" ],
                       [ "Humanities (incl. English)" => "HU" ],
                       [ "Professional (incl. Law and Medicine)" => "PL" ],
                       [ "Other Academic Subject" => "AC" ],
                       [ "Non-Academic" => "NA" ]);
             return [ \@area_class, style => 'width:150px' ];
               },
              },

              $fieldis{'hr_skip'},

              {
               name  => 'todolist',
               label => 'Message (ToDo) List for Yourself',
               default => "First complete your settings.",
               skip_on_reg => 1,
               tag_options => [ style => 'width:100ex', title => 'Private', placeholder => 'e.g., don\'t forget to fail student X' ]
              },

              $fieldis{'hr_skip'},

              {
               name  => 'message',
               label => 'Intro Message for Your Students',
               skip_on_reg => 1,
               tag_options => [ style => 'width:100ex', title => 'Public', placeholder => 'e.g., don\'t forget to take quiz A' ]
              },

              $fieldis{'hr_skip'},

              {
               name  => 'is_enabled_leaderboard',
               label => 'Enable student leaderboards',
               type  => 'checkbox',
               check => [is_in([1])],
               default => 1
              },
              {
               name  => 'is_print_answer',
               label => 'Explain answers to students after submit',
               type  => 'checkbox',
               check => is_in([1]),
               skip_on_reg => 1,
               default => 1,
              },
              {
               name  => 'qdl_password',
               label => 'Password required to view quizzes',
               skip_on_reg => 1,
               tag_options => [ title => 'Leave empty for no password' ]
              },
              {
               name  => 'rup_password',
               label => 'Password required to submit quizzes',
               skip_on_reg => 1,
               tag_options => [ title => 'Leave empty for no password' ]
              },

              $fieldis{'hr_skip'},
              $fieldis{'is_agree_with_usage_condition'},

             ],
       };
  }

sub _get_student_schema {
    my ($self, $config) = @_;
    return {
        layout        => 'student',
        user_type     => 'student',
        home_url      => 'students_show_home', # url or route name
        captcha       => $config->{user_manager}{captcha},
        email_confirm => $config->{user_manager}{email_confirm},
        site_url      => $config->{user_manager}{site_url},
        password_crypter => sub { $self->_crypt_password(@_) },
        session_expiration => 3600*24*7,
        login_labels  => {
            title    => "
<header>
  <table class=\"hdr\">
    <tr>
      <td> <span class='gravatar'> <img src='/static/img/equizavatar.jpg' alt='Gravatar' height='80' width='80' /> </span> &nbsp;&nbsp; </td>
      <td> <span class=\"hdruid\"> Students </span>
          <br />&nbsp;<br />
          <span class=\"hdrfid\"> Log In </span> </td>
    </tr>
    <tr> <td colspan=\"2\"> <span class=\"gravatarbottom\">Equiz.Me</span>
           <br />&nbsp;</td>
    </tr>
  </table>
</header>
<hr />",
            user_id  => 'Email',
            password => 'Password',
            submit    => 'Login'
        },
        registration_labels  => {
            title => "
<header>
  <table class=\"hdr\">
    <tr>
      <td> <span class='gravatar'> <img src='/static/img/equizavatar.jpg' alt='Gravatar' height='80' width='80' /> </span> &nbsp;&nbsp; </td>
      <td> <span class=\"hdruid\"> Students </span>
          <br />&nbsp;<br />
          <span class=\"hdrfid\"> Registration </span> </td>
    </tr>
    <tr> <td colspan=\"2\"> <span class=\"gravatarbottom\">Equiz.Me</span>
           <br />&nbsp;</td>
    </tr>
  </table>
</header>
<hr />",
        },
        profile_labels  => {
            title => '',
            page_title => 'Student Update Settings'
        },
        password_reminder_labels => {
            title => '<h1>Student Remind Password</h1>'
        },
        storage       => EQ::Model::Storages->get_students_storage(),
        plain_auth    => 1,
        fields    => [
              $fieldis{'email'},
              $fieldis{'user_id'},
              $fieldis{'password'},
              $fieldis{'password2'},

              {
             name  => 'student_id',
             label => 'Student (Registrar) Id <span class="req">+</span>',
             tag_options => [ 'maxlength' => 24,  title => "Private.  Instructor may not be able to give you a grade without it", placeholder => 'e.g., S123' ],
            },

              $fieldis{'first_name'},
              $fieldis{'last_name'},
              $fieldis{'ssn'},
              $fieldis{'gender'},
              $fieldis{'phone_number'},

              $fieldis{'hr_skip'},

              $fieldis{'institution'},
              $fieldis{'street'},
              $fieldis{'city'},
              $fieldis{'state'},
              $fieldis{'postal_code'},
              $fieldis{'country'},

              $fieldis{'hr_skip'},

            {
                name  => 'instructor_id',
                class => 'searchable',
                skip_on_reg => 1,
                allow_pass_default => 1,
                label => '<b>Default Instructor</b>',
                type  => 'select',
                tag_options => sub {
                    my $c = shift;
                    my @select_options = [ 'None' => '' ];
                    my $instructors = $c->um_storage('instructor')->list();

                    my $student_access = EQ::Model::StudentAccess->new(backend => $c->backend);
                    foreach my $instr (@$instructors) {
                        my $student_id = $c->session('user_id');
                        my $instructor_id = $instr->{user_id};
                        next unless $student_access->is_email_permitted($instructor_id, $student_id);

                        my $label = "$instr->{first_name} $instr->{last_name} - $instr->{institution} $instr->{class}";
                        push @select_options, [ $label => $instr->{user_id} ];
                    }
                    return [ \@select_options,  style => 'width:150px'];
                },
            },

              $fieldis{'hr_skip'},

           {
                name  => 'is_enabled_leaderboard',
                label => 'Participate in leaderboards',
                type  => 'checkbox',
                check => [is_in([1])],
                default => 1,
            },


              $fieldis{'hr_skip'},
           {
                name  => 'is_agree_with_usage_condition',
                label => 'Agree to <a target="_blank" href="/static/legal.html"> Legal Usage </a> Conditions',
                type  => 'checkbox',
                check => [ is_required('Agree to proceed'), is_in([1]) ],
            },
        ],
    };
}

sub _register_helpers {
    my ($self, $config) = @_;

    $self->helper(captcha_html => sub {
        my ($c) = @_;

        my $one = int(rand(11));
        my $two = int(rand(11));

        my $captcha = $one + $two;
        $c->session(captcha => Digest::MD5::md5_hex($captcha));

        return <<"EOF";
How much is $one + $two?
<input name="captcha" />
EOF
    });

    $self->helper(check_captcha => sub {
        my ($c) = @_;

        my $expected = $c->session('captcha');

        return $expected eq Digest::MD5::md5_hex($c->param('captcha'));
    });

    # "equiz_css" helper
    $self->helper( equiz_css => sub {
        my ($c, $instructor_id) = @_;
        return unless $instructor_id;

        my $backend = EQ::Plugin::FileManager::Model::Bucket->backend;

        my $css =
            $backend->file_exists($instructor_id, 'equiz.css')
          ? $backend->slurp_file($instructor_id, 'equiz.css')
          : '';

        my $html = "\n\n<!-- start inserting users own equiz.css file -->\n".
      "<link href=\"/static/equiz.css\" media=\"screen\" rel=\"stylesheet\" type=\"text/css\" />".
        "<style type=\"text/css\">\n" . b($css)->xml_escape() . "\n</style>\n".
          "<!-- end inserting users own equiz.css file -->\n\n";
        return b($html);
    });

    $self->helper(
        backend => sub { EQ::Plugin::FileManager::Model::Bucket->backend });

    $self->helper(uri_encode => sub { b(url_escape($_[1])) })
}

sub _crypt_password {
    my ($self, $pass, $u_data) = @_;
    my $sha2obj = Digest::SHA2->new();
    $sha2obj->add($pass);
    $sha2obj->add($sha2obj->digest(), $u_data->{user_id});
    return $sha2obj->hexdigest();
}

1;
