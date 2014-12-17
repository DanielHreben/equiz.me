package EQ::Plugin::FileManager::Model::Bucket::S3;

use v5.14;

use strict;
use warnings;

use File::Basename ();
use File::Path ();
use Digest::MD5 'md5_hex';
use Time::Piece;
use EQ::Plugin::FileManager::Model::Bucket::S3::Iterator;

use Net::Amazon::S3;

sub new {
    my $class = shift;

    my $self = {@_};
    bless $self, $class;

    die 'aws_access_key_id is required' unless $self->{aws_access_key_id};
    die 'aws_secret_access_key is required' unless $self->{aws_secret_access_key};

    $self->{s3} = Net::Amazon::S3->new(
        {   aws_access_key_id     => $self->{aws_access_key_id},
            aws_secret_access_key => $self->{aws_secret_access_key},
            retry                 => 1,
        }
    );

    return $self;
}

sub slurp_file {
    my $self = shift;
    my ($uid, $filename) = @_;

    my $s3 = $self->{s3};

    my $bucket = $self->_get_bucket($uid);

    my $response = $bucket->get_key($filename);
    return $response->{value};
}

sub open_file {
    my $self = shift;
    my ($uid, $filename) = @_;

    my $s3 = $self->{s3};

    my $bucket = $self->_get_bucket($uid);

    my $response = $bucket->get_key($filename);
    die "File does not exist\n" unless $response;

    my $content = $response->{value};

    open my $fh, '<', \$content;
    return $fh;
}

sub write_file {
    my $self = shift;
    my $content = pop;

    my $s3 = $self->{s3};

    my $bucket = $self->_get_bucket(@_);

    my $filename = pop;

    my $response = $bucket->get_key($filename);
    die "File exists" if $response;

    $bucket->add_key($filename, $content) or die $s3->errstr;

    return $self;
}

sub append_file {
    my $self = shift;
    my ($uid, $filename, $content) = @_;

    my $s3 = $self->{s3};

    my $bucket = $self->_get_bucket($uid);

    my $response = $bucket->get_key($filename);

    $content = $response->{value} . $content;

    $bucket->add_key($filename, $content) or die $s3->errstr;

    return $self;
}

sub overwrite_file {
    my $self = shift;
    my ($uid, $filename, $content) = @_;

    my $s3 = $self->{s3};

    my $bucket = $self->_get_bucket($uid);

    my $response = $bucket->get_key($filename);

    $bucket->add_key($filename, $content) or die $s3->errstr;

    return $self;
}

sub write_temp_file {
    my $self = shift;
    my ($contents, $filename) = @_;

    if ($filename) {
        my $dir = File::Temp->newdir(CLEANUP => 0);
        my $filename = File::Spec->catfile($dir, $filename);

        open my $temp, '>', $filename or die $!;
        print $temp $contents;

        return $filename;
    }
    else {
        my $temp = File::Temp->new(UNLINK => 0);
        open my $fh, '>', $temp or die $!;
        print $temp $contents;

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

    die 'It is the same file' if $from eq $dest;
    die 'This file exists' if $self->file_exists($uid, $dest);

    my $bucket = $self->_get_bucket($uid);
    $from = $bucket->get_key($from);

    $self->write_file($uid, $dest, $from->{value});

    $bucket->delete_key($from);

    return $self;
}

sub delete_file {
    my $self = shift;
    my ($uid, $filename) = @_;

    my $bucket = $self->_get_bucket($uid);
    $bucket->delete_key($filename) or die "Can't remove file\n";
}

sub check_file {
    my $self = shift;
    my ($uid, $file) = @_;

    my $bucket = $self->_get_bucket($uid);
    die "File does not exist" unless $bucket->get_key($file);

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

    die 'You need a user id' unless $uid;
    die "Your user id '$uid' is invalid" unless $self->_is_valid_uid($uid);

    return File::Spec->catfile($self->{rootdir}, md5_hex($uid), $filename);
}

sub uid {
    my $self = shift;
    my ($uid) = @_;

    return $uid if length($uid) == 32 && $uid =~ m/^[a-z0-9]+$/;

    return md5_hex($uid);
}

sub _is_valid_uid {
    my $self = shift;
    my ($uid) = @_;

    return $uid =~ m/^[a-zA-Z0-9][a-zA-Z0-9_\@\-.+]*[a-zA-Z0-9]$/i;
}

sub list_files {
    my $self = shift;
    my ($uid, %params) = @_;

    my $s3 = $self->{s3};

    my $bucket = $s3->bucket($self->uid($uid));

    my @files;

    my $response = $bucket->list_all or die $s3->err . ": " . $s3->errstr;
    foreach my $key (@{$response->{keys}}) {
        my $key_name = $key->{key};
        my $key_size = $key->{size};

        if ($params{exclude}) {
            next if $key_name =~ m/$params{exclude}/;
        }

        if ($params{match}) {
            next if $key_name !~ m/$params{match}/;
        }

        push @files, $key_name;
    }

    return @files;
}

sub get_file_size {
    my $self = shift;
    my ($uid, $filename) = @_;

    my $bucket = $self->_get_bucket($uid);

    my $response = $bucket->get_key($filename);
    return $response->{content_length};
}

sub get_file_mtime {
    my $self = shift;
    my ($uid, $filename) = @_;

    my $bucket = $self->_get_bucket($uid);

    my $response = $bucket->get_key($filename);

    my $mtime = $response->{'last-modified'};

    $mtime = Time::Piece->strptime($mtime);

    return $mtime->epoch;
}

sub file_exists {
    my $self = shift;

    my $bucket = $self->_get_bucket(@_);

    my $filename = pop;

    my $response = $bucket->get_key($filename);
    return $response ? 1 : 0;
}

sub get_file_iterator {
    my $self = shift;

    return EQ::Plugin::FileManager::Model::Bucket::S3::Iterator->new(
        s3 => $self->{s3} );
}

sub _get_bucket {
    my $self = shift;

    my $bucketname = @_ ? $self->uid($_[0]) : '.';

    my $s3 = $self->{s3};
    $s3->add_bucket({bucket => $bucketname});
    my $bucket = $s3->bucket($bucketname);

    return $bucket;
}

1;
