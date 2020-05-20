#!/usr/bin/perl
use strict;
use warnings;

my %fullpatients;


print STDERR "Reading year -5 patient medcodes\n";
open my $h1, "<", "../year1/medcodes.txt" or die "Can't open ../year1/medcodes.txt: $!\n"; 
while (<$h1>) {
    next unless /^\d/;
    my $id = (split /,/)[0];
    $fullpatients{$id} = $id;
}
close $h1;

print STDERR "Reading year -5 patient prodcodes\n";
open $h1, "<", "../year1/prodcodes.txt" or die "Can't open ../year1/prodcodes.txt: $!\n"; 
while (<$h1>) {
    next unless /^\d/;
    my $id = (split /,/)[0];
    $fullpatients{$id} = $id;
}


print STDERR "Filtering STDIN by year -5 patients\n";
while (<STDIN>) {
    unless (/^\d/) { print; next }

    my $id = (split /,/)[0];
    next unless $fullpatients{$id};

    print;

}


