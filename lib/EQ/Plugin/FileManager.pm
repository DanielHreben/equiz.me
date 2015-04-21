package EQ::Plugin::FileManager;

use v5.14;
use Mojo::Base 'Mojolicious::Plugin';
use EQ::Plugin::FileManager::Controller;
our $VERSION = '0.01';

use File::Basename qw/dirname/;
use File::Spec::Functions qw/rel2abs catdir/;
use Digest::MD5 qw/md5_hex/;

use EQ::Plugin::FileManager::Model::Bucket;

has 'config';

sub register {
    my ( $self, $app, $conf ) = @_;

    $self->_register_fm_hooks($conf);
    my $access_checker = $conf->{access_checker} || sub { 1 };

    $conf->{layout} ||= 'file_manager';
    $self->config($conf);

    # Append "templates" and "public" directories
    my $base = catdir(dirname(__FILE__), 'FileManager');
    push @{$app->renderer->paths}, catdir($base, 'templates');

    # Register "render_file_manager" helper
    $app->helper( render_file_manager => sub {
        my $c = shift;
        $self->_load_file_manager($conf, $c);
        EQ::Plugin::FileManager::Controller::fm($c);
    } );

    # Register "render_file_manager" helper
    $app->helper( fm_user_homedir => sub {
        my ($c, $user_id) = @_;
        #$self->_load_file_manager($conf, $c);

        my $root_dir = ref( $conf->{root_dir} ) eq 'CODE' ? $conf->{root_dir}->($c) : $conf->{root_dir};
        return catdir( $root_dir, md5_hex($user_id) );
    } );

    #Register "fm_config" helper
    $app->helper( fm_config => sub {
        return $self->config();
    } );

    my $routes = $conf->{routes} || $app->routes;

    # Guest routes
    my $fm_r = $routes->under('/fm')->to(
        cb => sub {
            my $c = shift;
            return 0 unless $access_checker->($c);
            $self->_load_file_manager($conf, $c)
        }
    )->route->to(
        controller => 'controller',
        namespace  => 'EQ::Plugin::FileManager'
    )->name('file_manager');

    $fm_r->any('/')             ->to('#fm')->name('file_manager_files');
    $fm_r->any('/index')        ->to('#index');
    $fm_r->any('/downloadfile') ->to('#downloadfile');
    $fm_r->any('/uploadfile')   ->to('#uploadfile');
    $fm_r->any('/viewfile')     ->to('#viewfile');
    $fm_r->any('/editfile')     ->to('#editfile');
    $fm_r->any('/submitfile')   ->to('#submitfile');
    $fm_r->any('/submitedit')   ->to('#submitedit');
    $fm_r->any('/renamefile')   ->to('#renamefile');
    $fm_r->any('/submitrename') ->to('#submitrename');
    $fm_r->any('/deletefile')   ->to('#deletefile');
    $fm_r->any('/extra')        ->to('#extra');
    $fm_r->any('/togglequiz')   ->to('#togglequiz');
}

sub _load_file_manager {
    my ($self, $conf, $c) = @_;
    #my $root_dir = ref( $conf->{root_dir} ) eq 'CODE' ? $conf->{root_dir}->($c) : $conf->{root_dir};
    my $user     = ref( $conf->{user} ) eq 'CODE' ? $conf->{user}->($c) : $conf->{user};

    #mkdir($root_dir) unless -e $root_dir;

    #my $user_dir = catdir( $root_dir, md5_hex($user) );
    #mkdir($user_dir) unless -e $user_dir;

    $c->session('uid' => $user);

    #EQ::Plugin::FileManager::Controller::Load( {
        #rootdir => $root_dir,
    #} );
}

sub _register_fm_hooks {
    my ($self, $conf) = @_;
    my $hooks = $conf->{hooks} || [];
    foreach my $h (@$hooks) {
        EQ::Plugin::FileManager::Controller::WithFile( $h->{name}, $h->{cb}, $h->{filter}, $h->{css} );
    }
}

1;
__END__

=head1 NAME

EQ::Plugin::FileManager - File Manager for Mojolicious applications

=head1 SYNOPSIS

      # Mojolicious::Lite
      plugin 'FileManager', {
        root_dir   => \&get_root_dir, # Can be string or callback
        size_limit => 100_000,
        hooks => [
            {
                name => 'Syntax Checker',
                cb => sub { my ($fname, $fh)= @_; return `perl -c $fname 2>&1`; },
                filter => qr/^[a-zA-Z_-]+\.p[lm]$/
            },
        ]
    };

    get '/' => sub {
        my $self = shift;
        $self->render_file_manager();
    };

    app->start;

    sub get_root_dir {
        my $c = shift;
        my $root = '/tmp/file_manager/';
        $c->session('uid' => 'test');
        return $root;
    }


=head1 DESCRIPTION

L<EQ::Plugin::FileManager> - File Manager for Mojolicious applications

=head1 HELPERS

=head2 render_file_manager

Renders file manager interface

=head1 METHODS

L<EQ::Plugin::FileManager> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

  $plugin->register;

Register plugin in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
