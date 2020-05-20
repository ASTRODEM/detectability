#!/usr/bin/perl
use strict;
use warnings;


my $type = $ARGV[0]; 
mkdir "/tmp/forest_$type"; 

foreach my $year (1..5) {
    my $diryear = "year$year"; 
    my $labelyear = 6 - $year;
       $labelyear = "-$labelyear";

    if (-e "$diryear/featurified_codes-$type-top_75_codes.txt") {
        print `cp $diryear/featurified_codes-$type-top_75_codes.txt /tmp/forest_$type/featurified_codes-$labelyear-years.txt`; 
    } else {
        print `cp $diryear/featurified_codes-$type-top_77_codes.txt /tmp/forest_$type/featurified_codes-$labelyear-years.txt`; 
    }
}

print `../../../code/random_forest.py /tmp/forest_$type/featurified_codes--5-years.txt /tmp/forest_$type/featurified_codes--4-years.txt /tmp/forest_$type/featurified_codes--3-years.txt /tmp/forest_$type/featurified_codes--2-years.txt /tmp/forest_$type/featurified_codes--1-years.txt`;

print `mv feature_weights_for_* plot.png /tmp/forest_$type`;
