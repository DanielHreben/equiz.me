#!/usr/bin/env perl

use v5.14;
use strict;
use warnings;

use File::Copy;

my ($file) = @ARGV;
die 'Usage: <file>' unless $file && -f $file;

die "Already processed: $file" if -f "$file.bak";
warn "Copying $file to $file.bak";
copy($file, "$file.bak") or die $!;

my @results = do { open my $fh, '<', $file or die $!; <$fh> };

warn "Processing $file";
foreach my $row (@results) {
    my $offset = 6;
    my @row = split /,/, $row;
if ($row[0] !~ m/-/) {
$offset--;
}
    splice(@row, $offset, 0, '');
    $row = join ',', @row;
}

warn "Saving $file";
open my $fh, '>', $file or die $!;
print $fh join '', @results;
close $fh;
