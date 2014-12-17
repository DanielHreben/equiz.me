package EQ::Plugin::UserManager::Controller::Sessions;

use v5.14;
use Mojo::Base 'Mojolicious::Controller';

use strict;
use warnings;

use File::Basename qw/dirname/;
use File::Spec::Functions qw/rel2abs/;
use Data::Dumper;
use Validate::Tiny ();

sub _get_ip {
    my $self = shift;

    my $headers = $self->req->headers;
    return
         $headers->header('x-forwarded-for')
      || $headers->header('x-real-ip')
      || $self->tx->remote_address;
}

sub create_form {
    my ( $self, $template ) = @_;

    my $user_id = $self->session('user_id');

    if ( $user_id && $self->session('user_type') eq $self->stash('user_type') ) {
        $self->redirect_to( $self->um_config->{home_url}, user_id => $user_id );
        return;
    }

    $self->render( 'sessions/create_form', layout => $self->um_config->{layout} );
}

sub create {
    my ($self)  = @_;

    my $result = $self->_validate_login;
    if (!$result->success ) {
        my $u_data = $self->user_data;
        $self->flash( %$u_data, $self->_get_error_messages($result));
        $self->redirect_to('auth_create_form');
        return;
    }

    my $user_id = $self->param('user_id');
    my $pass    = $self->param('password');

    my ($success, $error) = $self->_check_user_password( $user_id, $pass );
    if ($success) {

        # Check that user is activated
        my $u_data = $self->um_storage->get($user_id);
        unless ( $u_data->{_is_activated_by_user} ) {
            $self->flash(um_error => 'Account is inactive. You have not confirmed your registration yet!'
                  . ' Check your mail including a spam folder (gmail/yahoomail often work best)');
            $self->redirect_to('auth_create_form');
            return;
        }

        # Check that user is activated by admin
        unless ( $u_data->{_is_activated_by_admin} ) {
            $self->flash( um_error => 'Your account must be activated by administrator!' );
            $self->redirect_to('auth_create_form');
            return;
        }

        my $user_type = $self->stash('user_type');
        die "Cannot work without user_type" unless $user_type;

        $self->_update_expires();
        $self->session( 'user_id' => $user_id, 'user_type' => $user_type );

        $u_data->{last_login} = time;

        my $ip = $self->_get_ip;
        if (@{$u_data->{ip_log} || []} && $u_data->{ip_log}->[-1]->{ip} ne $ip) {
            $self->flash(um_notice => 'Your IP is different from the last one' );
        }

        my $log = [grep {$_->{ip} ne $ip} @{$u_data->{ip_log}}];
        push @{$log}, {ip => $ip, time => time};
        $u_data->{ip_log} = $log;

        $self->um_storage->set($u_data->{user_id}, $u_data );

        $self->redirect_to( $self->um_config->{home_url}, user_id => $user_id );
    } else {
        sleep 3;

        if ($error && $error eq 'Wrong password') {
            $self->flash(user_id => $user_id);
        }

        $self->flash( um_error => $error );
        $self->redirect_to('auth_create_form');
    }
}

sub delete {
    my ($self) = @_;
    $self->session( user_id => '' )->redirect_to('auth_create_form');
}

sub _validate_login {
    my ( $self ) = @_;

    return Validate::Tiny->new(
        {
            user_id => $self->param('user_id'),
            password => $self->param('password'),
        },
        {   fields => [qw/user_id password/],
            checks => [[qw/user_id password/] => Validate::Tiny::is_required()]
        }
    );
}

sub _get_error_messages {
    my ($self, $result) = @_;

    my $errors_hash = $result->error;
    my %errors = map { ("um_error_${_}" => $errors_hash->{$_} ) } keys %$errors_hash;

    return %errors;
}

sub _update_expires {
    # TODO remove dupication with UserManager::_session_update_expires
    my $self = shift;
    return unless $self->um_config->{session_expiration};
    $self->session( 'lifetime' => ( time + $self->um_config->{session_expiration} ) );
}

sub _check_user_password {
    my ( $self, $user_id, $password ) = @_;
    my $log = $self->app->log;

    unless ($user_id) {
        $log->debug("AUTH FAILED: No user_id");
        return (0);
    }

    unless ($password) {
        $log->debug("AUTH FAILED: user_id=[$user_id]. Empty password.");
        return (0);
    }

    local $Data::Dumper::Indent = 0;
    $log->debug("AUTH DEBUG: Login attempt user_id=[$user_id] password=[$password]" . Dumper($self->session) );

    my $config  = $self->um_config;
    my $storage = $self->um_storage;

    $log->debug("AUTH DEBUG: Getting data for user_id=[$user_id]");

    my $user_data = eval { $storage->get($user_id) };

    unless( $user_data && exists $user_data->{password} ) {
        $log->debug("AUTH FAILED: No data for user_id=[$user_id]");
        return (0, 'Unknown login');
    }

    if ( $config->{plain_auth} && $password eq $user_data->{password} ) {
        $log->debug("AUTH SUCCESS: Plain password login for user_id=[$user_id]");
        return (1);
    }

    if ( $config->{password_crypter}->($password, $user_data) eq $user_data->{password} ) {
        $log->debug("AUTH SUCCESS: Crypted password login for user_id=[$user_id]");
        return (1);
    }

    $log->debug("AUTH FAILED: Wrong password for user_id=[$user_id]");
    return (0, 'Wrong password');
}

1;
