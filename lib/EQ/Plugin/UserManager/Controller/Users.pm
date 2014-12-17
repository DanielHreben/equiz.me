package EQ::Plugin::UserManager::Controller::Users;

use v5.14;

use strict;
use warnings;

use Mojo::Base 'Mojolicious::Controller';
use Validate::Tiny;
use Digest::MD5 qw/md5_hex/;
use Mojo::ByteStream qw/b/;
use Time::Piece;

sub create_form {
    my $self = shift;
    my $user_id = $self->session('user_id');

    if ( $user_id && $self->session('user_type') eq $self->stash('user_type') ) {
        $self->redirect_to( $self->um_config->{home_url}, user_id => $user_id );
        return;
    }

    $self->stash( captcha => $self->um_config->{captcha} );
    $self->render( 'users/create_form', layout => $self->um_config->{layout} );
}

sub create {
    my ($self) = @_;
    my $conf = $self->um_config;

    my $result = $self->_validate_fields();
    my $u_data = $result->data;

    if ( $result->success ) {
        # Apply defaults for "skip_on_reg" fields
        foreach my $field ( @{ $self->um_config->{fields} } ) {
            next unless $field->{skip_on_reg};
            next unless exists $field->{default};
            $u_data->{ $field->{name} } = $field->{default} if length( $u_data->{ $field->{name} } ) == 0;
        }

        # Check captcha
        if ( $conf->{captcha} && !$self->check_captcha ) {
            $self->flash( %$u_data, um_error => 'Wrong CAPTCHA code' );
            $self->redirect_to('user_create_form');
            return;
        }

        # Check that user does not exists
        if ( $self->um_storage->get( $u_data->{user_id} ) ) {
            $self->flash( %$u_data, um_error => 'Such user already exists' );
            $self->redirect_to('user_create_form');
            return;
        }

        delete $u_data->{password2};

        # Crypt password
        my $plain_password = $u_data->{password};
        $u_data->{password} = $conf->{password_crypter}->( $plain_password, $u_data );

        # Send confirmation  email to admin
        if ( $conf->{admin_confirm} ) {
            my $activation_code = md5_hex( time + rand(time) );
            my $user_type = $self->stash('user_type');
            my $activation_url  = "$conf->{site_url}/$user_type/activation_by_admin/$activation_code";
            $u_data->{_is_activated_by_admin}       = 0;
            $u_data->{_activation_code_for_admin} = $activation_code;


            $self->app->log->info( "Sending registration email for [$u_data->{user_id}] to amin. Activation link [$activation_url]" );
            $self->_send_activation_email($conf->{admin_email}, $activation_url, $u_data );
        } else {
            $u_data->{_is_activated_by_admin} = 1;
        }

        # Send  confirmation  email to user
        if ( $conf->{email_confirm} && $u_data->{email} ) {
            my $activation_code = md5_hex( time + rand(time) );
            my $user_type = $self->stash('user_type');
            my $activation_url  = "$conf->{site_url}/$user_type/activation_by_user/$activation_code";
            $u_data->{_is_activated_by_user}       = 0;
            $u_data->{_activation_code_for_user} = $activation_code;

            $self->app->log->info( "Sending registration email for [$u_data->{user_id}] to [$u_data->{email}]. Activation link [$activation_url]" );
            $self->_send_activation_email( $u_data->{email}, $activation_url, $u_data );
        } else {
            $u_data->{_is_activated_by_user} = 1;
        }

        my $user_type = $self->stash('user_type');
        if ($user_type eq 'student' && $self->param('instructor_id')) {
            $u_data->{instructor_id} = $self->param('instructor_id');
        }

        # Save user
        $self->um_storage->set( $u_data->{user_id}, $u_data );


        # Call on_registration callback
        my $on_reg_cb = ref( $self->um_config->{on_registration} ) eq 'CODE' ? $self->um_config->{on_registration} : '';
        $on_reg_cb->($self, $u_data) if $on_reg_cb;


        # Redirect to login form
        $self->flash(
            um_notice => 'Registration completed - Check Email For Confirmation <b>including spam folders</b>; (gmail/yahoomail often work best)',
            user_id => $u_data->{user_id},
            password => $plain_password
        );
        $self->redirect_to('auth_create_form');
    } else {
        $self->flash( %$u_data, $self->_get_error_messages($result) );
        $self->redirect_to('user_create_form');
    }
}


sub update_form {
    my $self = shift;

    my $user_id = $self->session('user_id');

    my $secret = md5_hex $user_id;

    $self->render( 'users/update_form', layout => $self->um_config->{layout}, secret => $secret );
}

sub update {
    my ($self) = @_;
    my $conf = $self->um_config;

    my $result = $self->_validate_fields( [qw/password password2 user_id email/] );
    my $u_data = $result->data;

    # Check passwords
    if ( my $pass = $self->param('password') ) {
        if ( $pass ne $self->param('password2') ) {
            $self->flash( %$u_data, um_error => qq#Passwords do no coincide# );
            return $self->redirect_to('user_update_form');
        }
    }

    if ( $result->success ) {
        # Crypt password
        my $new_pass = $self->param('password');
        if ($new_pass) {
            $u_data->{user_id} = $self->stash('user_id');
            $u_data->{password} = $conf->{password_crypter}->($new_pass, $u_data);
        } else {
            delete $u_data->{password};
        }

        # Save user
        $self->um_storage->set( $self->stash('user_id'), $u_data );
        $self->flash( um_notice => 'Saved' )->redirect_to( $self->um_config->{home_url} );
    } else {
        $self->flash( %$u_data, $self->_get_error_messages($result))->redirect_to('user_update_form');
    }

}

sub delete {
    my ($self) = @_;
    my $conf = $self->um_config;

    my $user_id = $self->session('user_id');
    my $u_data = $self->um_storage->get($user_id);

    if (my $code = $self->param('code')) {
        if ($u_data->{_removal_code} eq $code) {
            $self->flash('um_notice' => 'Your account was deleted');

            $self->um_storage->del($user_id);
            $self->session( user_id => '' );
            return $self->redirect_to('auth_create_form');
        }
        else {
            $self->stash('um_notice' => 'Wrong removal code');
            $self->render( 'users/delete', layout => $self->um_config->{layout} );
        }
    }
    else {
        $self->stash('um_notice' => 'Check your E-mail');

        my $user_type = $self->stash('user_type');
        my $removal_code = md5_hex( time + rand(time) );
        my $removal_url  = "$conf->{site_url}/$user_type/users/$user_id/delete?code=$removal_code";

        $u_data->{_removal_code} = $removal_code;
        $self->um_storage->set($user_id, $u_data);

        $self->mail(
           to      => $u_data->{email},
           subject => "User [ $u_data->{user_id} ] removal",
           data    => "To remove [$u_data->{user_id}] account go to $removal_url",
        );

        $self->render( 'users/delete', layout => $self->um_config->{layout} );
    }
}

sub iplog {
    my $self = shift;
    my $conf = $self->um_config;

    my $user_id = $self->session('user_id');
    my $u_data = $self->um_storage->get($user_id);

    my $iplog = $u_data->{ip_log} || [];

    foreach my $log (@$iplog) {
        $log->{time} = Time::Piece->new($log->{time})->strftime('%Y-%m-%d %T');
    }

    $self->render( 'users/iplog', layout => $self->um_config->{layout}, iplog => $iplog );
}

sub admin {
    my ($self) = @_;
    my $conf = $self->um_config;

    my $users = [];

    my $instructors = EQ::Model::Instructors->get_all_instructors();
    foreach my $instructor (@$instructors) {
        $instructor->{last_login} = Time::Piece->new($instructor->{last_login})->strftime('%Y-%m-%d %T');
        $instructor->{type} = 'instructor';
        push @$users, @$instructors;
    }

    my $students = EQ::Model::Students->get_all_students();
    foreach my $student (@$students) {
        $student->{last_login} = Time::Piece->new($student->{last_login})->strftime('%Y-%m-%d %T');
        $student->{type} = 'student';
        push @$users, @$students;
    }

    $users = [sort { $a->{user_id} cmp $b->{user_id} } @$users];

    $self->stash(users => $users);

    $self->render( 'admins/panel', layout => $self->um_config->{layout});
}

sub update_password_form {
    my $self = shift;
    $self->render( 'users/update_password_form', layout => $self->um_config->{layout} );
}


sub update_password {
    my ($self) = @_;
    my $conf = $self->um_config;

    my $result = $self->_validate_password();
    my $u_data = $self->user_data;

    if ( $result->success ) {
        # Crypt password
        my $new_pass = $self->param('password');
        $u_data->{password} = $conf->{password_crypter}->($new_pass, $u_data);

        # Save user
        $self->um_storage->set( $self->stash('user_id'), $u_data );
        $self->flash( um_notice => 'Saved' )->redirect_to( $self->um_config->{home_url} );
    } else {
        $self->flash( %$u_data, $self->_get_error_messages($result))->redirect_to('user_update_password_form');
    }

}

sub unsubscribe_form {
    my $self = shift;

    my $u_data = $self->user_data;

    if ($u_data->{unsubscribed}) {
        $self->stash('already_unsubscribed' => 1);
    }

    $self->render( 'users/unsubscribe_form', layout => $self->um_config->{layout} );
}

sub unsubscribe {
    my ($self) = @_;

    my $conf = $self->um_config;

    my $u_data = $self->user_data;

    $u_data->{unsubscribed} = 1;

    $self->um_storage->set($self->stash('user_id'), $u_data);
    $self->flash( um_notice => 'Unsubscribed from email notifications' )->redirect_to( $self->um_config->{home_url} );
}

sub activation_by_user {
    my ($self) = @_;
    my $act_code = $self->param('activation_code');
    return $self->render( text => "Wrong activation code") unless $act_code =~ /^[0-9a-f]{32}$/i;

    # TODO acvation link must contain user_id
    my $users = $self->um_storage->list([ _activation_code_for_user => $act_code ]);

    if ($users && @$users) {
        my $u_data = $users->[0];

        $self->um_storage->set( $u_data->{user_id}, { _is_activated_by_user => 1 } );
        $self->flash( um_notice => "User [$u_data->{user_id}] activated.<br />(Instructors also require site approval.  Students are now activated and able to log in.)", user_id => $u_data->{user_id} );
        $self->redirect_to('auth_create_form');
    } else {
        $self->render( text => "Wrong activation code");
    }
}

sub activation_by_admin {
    my ($self) = @_;
    my $act_code = $self->param('activation_code');
    return $self->render( text => "Wrong activation code") unless $act_code =~ /^[0-9a-f]{32}$/i;

    # TODO acvation link must contan user_id
    my $users = $self->um_storage->list([ _activation_code_for_admin => $act_code ]);

    if ($users && @$users) {
        my $u_data = $users->[0];

        $self->um_storage->set( $u_data->{user_id}, { _is_activated_by_admin => 1 } );
        $self->flash( um_notice => "User [$u_data->{user_id}] activated", user_id => $u_data->{user_id} );
        $self->redirect_to('auth_create_form');
    } else {
        $self->render( text => "Wrong activation code");
    }
}

sub remind_password_form {
    my $self = shift;
    my $user_id = $self->session('user_id');

    if ( $user_id && $self->session('user_type') eq $self->stash('user_type') ) {
        $self->redirect_to( $self->um_config->{home_url}, user_id => $user_id );
        return;
    }

    $self->render( 'users/remind_password_form', layout => $self->um_config->{layout} );
}


sub remind_password {
    my ($self) = @_;
    my $user_id = $self->param('user_id');
    my $u_data = eval{ $self->um_storage->get($user_id) };

    return $self->flash('um_error' => 'Wrong Login')->redirect_to('user_remind_password_form') unless ref $u_data;

    my $conf = $self->um_config;
    my $autologin_code = md5_hex( time + rand(time) );
    my $user_type = $self->stash('user_type');
    my $autologin_url  = "$conf->{site_url}/$user_type/autologin/$autologin_code";

    $self->um_storage->set( $user_id, {_autologin_code => $autologin_code } );

    $self->app->log->debug( "To login [$u_data->{user_id}] account and change password go to $autologin_url" );

    $self->app->log->info( "Sending password recovery email for [$u_data->{user_id}] to [$u_data->{email}]. Recovery link [$autologin_url]" );
    $self->mail(
        to      => $u_data->{email},
        subject => "User [ $u_data->{user_id} ] password recovery",
        data    => "To login [$u_data->{user_id}] account and change password go to $autologin_url",
    );

    $self->flash('um_notice' => 'Check your E-mail')->redirect_to('auth_create_form');
}

sub autologin {
    my ($self) = @_;
    my $code = $self->param('autologin_code');
    return $self->render( text => "Wrong code") unless $code =~ /^[0-9a-f]{32}$/i;

    # TODO autologin link must contain user_id
    my $users = $self->um_storage->list([ _autologin_code => $code ]);

    if ($users && @$users) {
        my $u_data = $users->[0];
        # TODO move this to Sessions controller
        unless ( $u_data->{_is_activated_by_admin} ) {
            $self->flash( um_error => 'User is not active!' );
            $self->redirect_to('user_remind_password_form');
            return;
        }

        $self->um_storage->set( $u_data->{user_id}, { _autologin_code => '', _is_activated_by_user => 1 } );

        # TODO move session update to Sessions controller
        $self->flash('um_notice' => 'Please, change your password');
        $self->session( 'user_id' => $u_data->{user_id}, 'user_type' => $self->stash('user_type'), lifetime => (time + 3600) );
        $self->redirect_to('user_update_form', user_id => $u_data->{user_id});
    } else {
        $self->render( text => "Wrong password recovery code");
    }
}

sub _validate_password {
    my ( $self ) = @_;
    my $schema = $self->um_config->{fields};

    my @fields = (qw/password password2/);
    my @checks = map { $_->{name} => $_->{check} } grep { $_->{check} } @$schema;
    my %input  = map { $_, ($self->param($_)//'') } @fields;

    return Validate::Tiny->new( \%input, { fields => \@fields, checks => \@checks } );
}

sub _validate_fields {
    my ( $self, $skip ) = @_;

    my $schema = $self->um_config->{fields};
    my @fields = map { $_->{name} ~~ $skip ? () : $_->{name} } @$schema;
    my @checks = map { $_->{name} => $_->{check} } grep { $_->{check} } @$schema;
    my %input  = map { $_, ($self->param($_)//'') } @fields;

    return Validate::Tiny->new( \%input, { fields => \@fields, checks => \@checks } );
}

sub _get_error_messages {
    my ($self, $result) = @_;

    my $errors_hash = $result->error;
    my %errors = map { ("um_error_${_}" => $errors_hash->{$_} ) } keys %$errors_hash;

    return %errors;
}

sub _send_activation_email {
    my ($self, $emails, $activation_url, $u_data) = @_;
    my $schema = $self->um_config->{fields};

    my $user_info = "New user info:\n";

    foreach my $field (@$schema) {
        next if $field->{name} =~ /password/;

        my $label = $field->{name};
        my $value = $u_data->{$field->{name}} // '';

        next unless $label && $value;

        $user_info .= "$label: $value \n";
    }

    $emails = [$emails] unless ref $emails eq 'ARRAY';

    foreach my $email (@$emails) {
        $self->mail(
            to      => $email,
            subject => "User [ $u_data->{user_id} ] activation",
            data    => <<"EOF",
To activate [$u_data->{user_id}] go to $activation_url \n\n $user_info.

Our system is set up so that you have a second password you can use to log in.
It is deliberately impossible to remember, but it is always a fallback. This
password is $u_data->{password}. Keep this email safe in your mailbox in case
you run into trouble.
EOF
        );
    }
}


1;
