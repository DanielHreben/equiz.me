package EQ::Model;

use v5.14;

use strict;
use warnings;

use EQ::Model::Storages;
use EQ::Model::Instructors;
use EQ::Model::Students;
use EQ::Model::Quizzes;
use EQ::Model::Results;

sub init {
    my ($class, $config) = @_;
    $class->_set_config($config);

    return $class;
}


{
    my $CONFIG;

    sub _set_config {
        my ($class, $config) = @_;
        die '"storage_root" required!'  unless $config->{storage_root};
        die '"instructors_root" required!'  unless $config->{instructors_root};

        $CONFIG = $config;

        return $class;
    }

    sub get_config {
        die "Model was not initialized" unless $CONFIG;
    }
}

1;
