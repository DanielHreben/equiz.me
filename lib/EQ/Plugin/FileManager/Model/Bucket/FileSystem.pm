package EQ::Plugin::FileManager::Model::Bucket::FileSystem;

use v5.14;

use strict;
use warnings;

use Fcntl qw/:flock/;
use File::Temp     ();
use File::Basename ();
use File::Path ();
use Digest::MD5 'md5_hex';
use EQ::Plugin::FileManager::Model::Bucket::FileSystem::Iterator;

sub new {
    my $class = shift;

    my $self = {@_};
    bless $self, $class;

    # I know. This is fucking stupid.
    my $rootdir = $self->{rootdir} || $self->{root_dir};
    $self->{rootdir} = $rootdir;

    (defined($self->{rootdir})) or die "You need to set up the rootdir.";
    (-e "$self->{rootdir}")
      or die "Your rootdir $self->{rootdir} does not exist.";
    (-r "$self->{rootdir}")
      or die "Your rootdir $self->{rootdir} is not readable.";
    (-r "$self->{rootdir}")
      or die "Your rootdir $self->{rootdir} is not writable.";

    return $self;
}

sub slurp_file {
    my $self = shift;
    my ($uid, $filename) = @_;

    my $fh = $self->open_file($uid, $filename);
    return do { local $/; <$fh> };
}

sub open_file {
    my $self = shift;
    my ($uid, $filename) = @_;

    my $path = $self->_resolve_path($uid, $filename);

    die "File '$path' does not exist\n"  unless -e $path;
    die "File '$path' is not readable\n" unless -r $path;

    open my $fh, '<:encoding(UTF-8)', $path or die $!;

    return $fh;
}

sub write_file {
    my $self = shift;
    my $content = pop;

    my $path = @_ == 2 ? $self->_resolve_path(@_) : $self->resolve_root_path(@_);

    die "File exists" if -e $path;

    File::Path::make_path(File::Basename::dirname($path));

    open my $fh, '>', $path or die $!;
    $content = Encode::encode('UTF-8', $content) if Encode::is_utf8($content);
    print $fh $content;

    return $self;
}

sub append_file {
    my $self = shift;
    my ($uid, $filename, $content) = @_;

    my $path = $self->_resolve_path($uid, $filename);

    open ( my $fh, '>>', $path ) or die "Cannot open file [$path]. $!";
    flock( $fh, LOCK_EX ) or die "Cannot lock file [$path] - $!\n";
    $content = Encode::encode('UTF-8', $content) if Encode::is_utf8($content);
    print $fh $content, "\n";
    close $fh;
}

sub overwrite_file {
    my $self = shift;
    my ($uid, $filename, $content) = @_;

    my $path = $self->_resolve_path($uid, $filename);

    open my $fh, '>', $path or die $!;
    $content = Encode::encode('UTF-8', $content) if Encode::is_utf8($content);
    print $fh $content;

    return $self;
}

sub write_temp_file {
    my $self = shift;
    my ($content, $filename) = @_;

    $content = Encode::encode('UTF-8', $content) if Encode::is_utf8($content);

    if ($filename) {
        my $dir = File::Temp->newdir(CLEANUP => 0);
        my $filename = File::Spec->catfile($dir, $filename);

        open my $temp, '>', $filename or die $!;
        print $temp $content;

        return $filename;
    }
    else {
        my $temp = File::Temp->new(UNLINK => 0);
        open my $fh, '>', $temp or die $!;
        print $temp $content;

        return $temp->filename;
    }
}

sub write_file_from_path {
    my $self = shift;
    my ($uid, $filename, $source_path) = @_;

    open my $fh, '<', $source_path or die $!;
    my $contents = do { local $/; <$fh> };

    $self->write_file($uid, $filename, $contents);
}

sub rename_file {
    my $self = shift;
    my ($uid, $from, $dest) = @_;

    $from = $self->_resolve_path($uid, $from);
    $dest = $self->_resolve_path($uid, $dest);

    die 'It is the same file' if $from eq $dest;
    die 'This file exists' if -e $dest;

    rename($from, $dest);

    return $self;
}

sub delete_file {
    my $self = shift;
    my ($uid, $filename) = @_;

    my $path = $self->_resolve_path($uid, $filename);

    unlink $path or die "Can't remove file";
}

sub check_file {
    my $self = shift;
    my ($uid, $file) = @_;

    my $path = $self->_resolve_path($uid, $file);

    die 'File does not exist'  unless -e $path;
    die 'File is not readable' unless -r $path;
    die 'File is not writable' unless -w $path;

    return;
}

sub htmlify {
    my $self = shift;
    my ($text) = @_;

    for ($text) {
        s/\&/&amp;/gsm;
        s/\</&lt;/gsm;
        s/\>/&gt;/gsm;
        s/\n/<br \/>\n/gsm;
    }

    return qq(<div class="viewfile">$text</div>);
}

sub resolve_uid {
    my $self = shift;
    my ($uid) = @_;

    return md5_hex($uid);
}

sub _resolve_path {
    my $self = shift;
    my ($uid, $filename) = @_;

    if (length($uid) == 32 && $uid =~ m/^[a-z0-9]+$/) {
        return File::Spec->catfile($self->{rootdir}, $uid, $filename);
    }

    die 'You need a user id' unless $uid;
    die "Your user id '$uid' is invalid" unless $self->_is_valid_uid($uid);
    return File::Spec->catfile($self->{rootdir}, md5_hex($uid), $filename);
}

sub resolve_root_path {
    my $self = shift;
    my ($filename) = @_;

    return File::Spec->catfile($self->{rootdir}, $filename);
}

sub _is_valid_uid {
    my $self = shift;
    my ($uid) = @_;

    return $uid =~ m/^[a-zA-Z0-9][a-zA-Z0-9_\@\-.+]*[a-zA-Z0-9]$/i;
}

sub list_files {
    my $self = shift;
    my ($uid, %params) = @_;

    my $path = $self->_resolve_path($uid);

    my @files = glob "$path/*";

    if ($params{exclude}) {
        @files = grep { !m/$params{exclude}/ } @files;
    }

    if ($params{match}) {
        @files = grep {m/$params{match}/} @files;
    }

    return map { Encode::decode('UTF-8', File::Basename::basename($_)) } @files;
}

sub get_file_size {
    my $self = shift;
    my ($uid, $filename) = @_;

    my $path = $self->_resolve_path($uid, $filename);

    return (stat($path))[7];
}

sub get_file_mtime {
    my $self = shift;

    my $path = @_ == 2 ? $self->_resolve_path(@_) : $self->resolve_root_path(@_);

    return (stat($path))[9];
}

sub file_exists {
    my $self = shift;

    my $path = @_ == 2 ? $self->_resolve_path(@_) : $self->resolve_root_path(@_);

    return -e $path;
}

sub get_file_iterator {
    my $self = shift;

    return EQ::Plugin::FileManager::Model::Bucket::FileSystem::Iterator->new(
        root => $self->{rootdir} );
}

1;
