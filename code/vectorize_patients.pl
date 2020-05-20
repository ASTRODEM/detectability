#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;

my %patients;
my %codes;
my %codes_patientcount;
my %codes_casecount;
my %codes_controlscount;

my %excluded_patients;


my $year = 'everything';
my $top_k = 'all';

if (scalar @ARGV) {
    $year = shift @ARGV;
}

if (scalar @ARGV) {
    $top_k = shift @ARGV;
}

# here is the place to include code lists to map single codes to concepts
# read code lists to map single medcodes to

print "\n### Reading code lists\n";

print "... medcodes\n";
my %code_list_map = &load_codelist('../data/code_lists/medcodes/included','m');
print "... prodcodes\n";
   %code_list_map = (%code_list_map, &load_codelist('../data/code_lists/prodcodes/included','p'));


sub load_codelist {
    my $list_dir = shift;
    my $prefix   = shift;

    my %code_list_map;

    while (<$list_dir/*.txt>) {
        my $listname = $_;
        open my $list, "<", $listname or die "Can't open $listname: $!\n";
        $listname =~ s/\.txt//;
        $listname =~ s/^([^\/]+\/)+//;
        print "..... $listname\n";
        while (<$list>) {
            next if /^medcode/; #skip first line
            next if /^prodcode/; #skip first line
            next if /^0\s/; #skip dummy entries
            my @parts = split /\t/;
            my $code = shift @parts;
            $code =~ s/\s//g;
            $code_list_map{"$prefix-$code"} = "$prefix-$listname";
        }
    }
    return %code_list_map;
}

#print Data::Dumper::Dumper(\%code_list_map);




print "\n### Reading dementia code lists\n";

my %dementia_codes;
# read dementia code lists
while (<../data/code_lists/dementia_subtype_lists/*.txt>) {
    my $listname = $_;
    open my $list, "<", $listname or die "Can't open $listname: $!\n";
    $listname =~ s/\.txt//;
    $listname =~ s/^([^\/]+\/)+//;
    print "..... $listname\n";
    while (<$list>) {
        next if /^medcode/; #skip first line
        next if /^0\s/; #skip dummy entries
        my @parts = split /\t/;
        my $code = shift @parts;
        $code =~ s/\s//g;
        $dementia_codes{$code} = $listname;
    }
}

my $delirium_unspecified = '53924';








# read case list to identify patients and corresponding controls --> to reduce sample size for testing different clustring setups

print "\n### 1a. Reading patient / controls data from Matching_File.txt\n";

my %patient_controls_map;
my %controls_patient_map;
my %cases;
my %cases_list;
my %controls;
my %controls_list;
my %genders;
my %ages;

open my $matchfile, "<", '../data/patients/Matching_File.txt' or die "Can't open ../data/patients/Matching_File.txt: $!\n";
while (<$matchfile>) {
    next unless /^\d/;
    my @parts = split /\t/;
    my ($pat, $control, $pat_gender, $control_gender, $pat_byear, $index_date) = @parts[0,6,2,8,3,4];
    $cases_list{$pat}++;
    $genders{$pat} = $pat_gender;
    my $index_year = (split /\//, $index_date)[2];
    my $pat_age = $index_year - $pat_byear;
    $ages{$pat} = $pat_age;
    warn "Control $control already assigned to patient $controls_patient_map{$control}; not reassigning to $pat\n" if $controls_patient_map{$control};
    #warn "untypical control id [$control]; skipping\n" unless $control =~ /^\d+$/;
    next unless $control =~ /^\d+$/;
    $patient_controls_map{$pat} = $control;
    $controls_patient_map{$control} = $pat;
    $controls_list{$control}++;
    $genders{$control} = $control_gender;
    $ages{$control} = $pat_age; # control matched by age at index date!
}
close $matchfile;

print "... loaded ", scalar keys %cases_list, " cases and ", scalar keys %controls_list, " controls (total:", (scalar keys %cases_list) + (scalar keys %controls_list),")\n";

#print Data::Dumper::Dumper(\%good_patients);



print "\n### 1b. Reading patients' medcode and prodcode data\n";


# track patients with only the delirium unspecified code as dementia label (to remove later on)
my %seen_controls_with_dementia_code;

# note: hear we read all code data (not yearwise) to catch all codes and allow patient stratification (patient will most likely not have the diagnosis code in year 1, for instance)
open my $mf, "<", "../data/patients/medcodes.txt" or die "Can't open ../data/patients/medcodes.txt: $!\n";

#print "... first pass: stratifying cases and detecting bad cases\n";
while (<$mf>) {
    chomp;
    my ($pat, $code) = split /,/;

    # filter to only include controls that don't have a dementia code;

    if (defined $dementia_codes{$code}) {

        if (defined $controls_list{$pat}) {
            $seen_controls_with_dementia_code{$pat}{$code}++;
            next;
        }
    }
}

close $mf or die "Can't close ../data/patients/medcodes.txt: $!\n";

print "\n### 2. ", scalar keys %seen_controls_with_dementia_code, " controls found with dementia code; removing them including their respective matched cases\n";
# print "..... $_: ", join(", ", keys %{$seen_controls_with_dementia_code{$_}}) foreach keys %seen_controls_with_dementia_code;
foreach my $bad_control (keys %seen_controls_with_dementia_code) {
    my $matched_case = $controls_patient_map{$bad_control};
    delete $cases_list{$matched_case};
    delete $controls_list{$bad_control};
}
print "... remaining: ", scalar keys %cases_list, " cases and ", scalar keys %controls_list, " controls (total:", (scalar keys %cases_list) + (scalar keys %controls_list),")\n";



my @patients_wo_control = grep { not defined $patient_controls_map{$_} } keys %cases_list;
print "\n### 3. ", scalar @patients_wo_control, " cases found without matched control; removing\n";
foreach my $bad_case (@patients_wo_control) {
    delete $cases_list{$bad_case};
}

print "... remaining: ", scalar keys %cases_list, " cases and ", scalar keys %controls_list, " controls (total:", (scalar keys %cases_list) + (scalar keys %controls_list),")\n";



### remove cases with only delierium unspecified
my %patient_has_delirium_unspecified;
my %patient_has_proper_dementia_code;
my %cases_by_dementia_type;
my %seen_dementia_types;
my %seen_patients_with_more_than_one_dementia_type;

open $mf, "<", "../data/patients/medcodes.txt" or die "Can't open ../data/patients/medcodes.txt: $!\n";
while (<$mf>) {
    chomp;
    my ($pat, $code) = split /,/;

    # filter to only include patients in good_patients list (e.g., only a subset of the patients)
    #next unless $good_patients{$pat};

    next unless $cases_list{$pat};
    if (defined $dementia_codes{$code}) {

        if ($code eq $delirium_unspecified) {
            $patient_has_delirium_unspecified{$pat}++;
        } else {
            $patient_has_proper_dementia_code{$pat}++;
            push @{$cases_by_dementia_type{$dementia_codes{$code}}}, $pat unless $seen_dementia_types{$pat};
            push @{$cases_by_dementia_type{all}}, $pat unless defined $seen_dementia_types{$pat};
            if (my $t = $seen_dementia_types{$pat}) {  # intentional single =
                if ($t ne $dementia_codes{$code}) {
                    $seen_patients_with_more_than_one_dementia_type{$pat}{$t}++;
                    $seen_patients_with_more_than_one_dementia_type{$pat}{$dementia_codes{$code}}++;
                }
            } else {
                $seen_dementia_types{$pat} = $dementia_codes{$code};
            }
        }
    }
}

#foreach my $type (keys %cases_by_dementia_type) {
#    print "... ", scalar @{$cases_by_dementia_type{$type}}, " $type cases found\n";
#}


my $delir = 0;
foreach (keys %patient_has_delirium_unspecified) {
    next if $patient_has_proper_dementia_code{$_};
    delete $controls_list{$patient_controls_map{$_}};
    delete $cases_list{$_};
    $delir++;
}
print "\n ### 4a. $delir cases found where delirium unspecified is the only dementia code; removing together with their matched controls\n";
print "... remaining: ", scalar keys %cases_list, " cases and ", scalar keys %controls_list, " controls (total:", (scalar keys %cases_list) + (scalar keys %controls_list),")\n";
#print "... $delir cases will be removed where 'delirium unspecified' is the only dementia code\n";
#print "... ".(scalar keys %excluded_patients)." cases will be removed where more than one proper dementia type (not 'unspecified') is assigned\n";


# remove cases w/o dementia code
my $nocode = 0;
my @cases_so_far = keys %cases_list;
foreach (@cases_so_far) {
    next if $patient_has_proper_dementia_code{$_};
    delete $controls_list{$patient_controls_map{$_}};
    delete $cases_list{$_};
    $nocode++;
}
print "\n### 4b. $nocode cases found without dementia code; removing together with their matched controls\n";
print "... remaining: ", scalar keys %cases_list, " cases and ", scalar keys %controls_list, " controls (total:", (scalar keys %cases_list) + (scalar keys %controls_list),")\n";


print "\n\n... NOTE: ", scalar keys %seen_patients_with_more_than_one_dementia_type, " cases have more than 1 different types of dementia assigned\n";
if (scalar keys %seen_patients_with_more_than_one_dementia_type) {
    my %combos;
    while (my ($pat, $types) = each %seen_patients_with_more_than_one_dementia_type) {
        $combos{join '-', sort keys %$types}++;
        # if the patient has a proper dementia type + unspecified assigned: keep
        # if the patient has another combo of two, or more that two dementia types: exclude
        if (scalar keys %$types > 2 or not defined $types->{'unspecified'}) {
            $excluded_patients{$pat}++;
        }
    }
    foreach my $combo (sort keys %combos) {
        print "..... $combos{$combo} $combo\n";
    }
}

print "... keeping all for full analysis\n";
print "... only keeping alzheimers and alzheimers-unspecified for alzheimers analysis\n";
print "... only keeping vascular and vascular-unspecified for vascular analysis\n";


close $mf;



print "\n\n### Processing patients yearwise\n";
print "... loading patients in year $year\n";

&load_patient_data("../data/patients/yearwise/$year/medcodes.txt","m");
&load_patient_data("../data/patients/yearwise/$year/prodcodes.txt","p");

sub load_patient_data {
    my $file = shift;
    my $code_prefix = shift;

    open my $fh, "<", $file or die "Can't read $file: $!\n";

    while (<$fh>) {

        chomp;
        my ($pat, $code) = split /,/;

        #$next unless $good_patients{$pat};

        ### remove cases that only have 'delirium unspecified' as diagnosis and no other dementia diagnosis
        ### and remove their matched controls, too
        #next if ($patient_has_delirium_unspecified{$pat} and not $patient_has_proper_dementia_code{$pat});
        #next if ($controls_list{$pat} and $patient_has_delirium_unspecified{$controls_patient_map{$pat}} and not $patient_has_proper_dementia_code{$controls_patient_map{$pat}});
        #next if ($excluded_patients{$pat} or (defined $controls_patient_map{$pat} and $excluded_patients{$controls_patient_map{$pat}}));

        # now we have all of the above managed by deletions from the cases_list and controls_list, resp;
        next unless $cases_list{$pat} or $controls_list{$pat};

        # NOTE: Here we exclude patients which have no code represented by any on of our code lists
        # This also excludes controls for patients that are themselves included.
        # Is this good? --> probably not. Now commented next statement and added 'other' code type
        # to catch such cases
        #
        # .. edit Mai 2019 for final paper: other seems to be playing an important role in the
        # random forrest feature list. But we can't explain at all what that means (it seems to mean:
        # there are other codes that play an important role other that the ones defined in the code
        # lists we currently use). Hence, we remove non-codelisted codes for now again
        next unless $code_list_map{"$code_prefix-$code"};

        #print "Found code mapping for code $code: $code_list_map{$code}\n" if $code_list_map{$code};
        if ($code_list_map{"$code_prefix-$code"}) {
            $code = $code_list_map{"$code_prefix-$code"};
        } else {
            $code = "$code_prefix-other";
        }


        $patients{$pat}{codes}{$code}++;
        $cases{$pat}{codes}{$code}++ if $cases_list{$pat};
        $controls{$pat}{codes}{$code}++ if $controls_list{$pat};
        $codes{$code}++;
        $codes_patientcount{$code}++ unless $patients{$pat}{codes}{$code} > 1;
        $codes_casecount{$code}++ unless !$cases_list{$pat} || $cases{$pat}{codes}{$code} > 1;
        $codes_controlscount{$code}++ unless !$controls_list{$pat} || $controls{$pat}{codes}{$code} > 1;
    }

    close $fh or die "Can't close $file: $!\n";
}

my $casecount = scalar keys %cases;
my $controlcount = scalar keys %controls;
my $patientcount = scalar keys %patients;
print "\n### 5. found $casecount cases and $controlcount controls with at least one medcode or prodcode from our feature list (total: $patientcount patients)\n";
print "... This means that ", (scalar keys %cases_list) - $casecount, " cases and ", (scalar keys %controls_list) - $controlcount , " controls have no features in the study range of year $year\n";
print "... keeping all nonetheless\n";
#print "... will skip cases with 0 codes and their matched controls\n";



#foreach my $candidate (keys %patient_controls_map) {
#    print "--- lost case $candidate\n" unless $cases{$candidate} or ($patient_has_delirium_unspecified{$candidate} and not $patient_has_proper_dementia_code{$candidate});
#}

#foreach my $candidate (keys %controls_patient_map) {
#    print "--- lost control $candidate\n" unless $controls{$candidate} or ($patient_has_delirium_unspecified{$controls_patient_map{$candidate}} and not $patient_has_proper_dementia_code{$controls_patient_map{$candidate}});
#}





print "\n### Selecting features: \n";


my @code_keys = keys %codes;


my $feature_count = scalar @code_keys;

if ($top_k eq 'all') { # otherwise gotten from cli, see top of script
    $top_k = $feature_count;
};

my $top_k_index = $top_k - 1;


# this select medcodes/codelists to use based on absolute frequency
# my @medcode_keys = grep { $medcodes_patientcount{$_} > 1500 && $medcodes_patientcount{$_} < 75000 } keys %medcodes;
# my @prodcode_keys = grep { $prodcodes_patientcount{$_} > 1000 && $prodcodes_patientcount{$_} < 75000 } keys %prodcodes;

# this selects medcodes/codelists to use based on difference between case and control frequency - picking the top X features ranked by this difference

$codes_casecount{$_} ||= 0 foreach keys %codes_controlscount;
$codes_controlscount{$_} ||= 0 foreach keys %codes_casecount;

@code_keys = sort { ($codes_casecount{$b} - $codes_controlscount{$b}) <=> ($codes_casecount{$a} - $codes_controlscount{$a}) } keys %codes;
@code_keys = @code_keys[0..$top_k_index]; # 0..X top features

#print "... using all code lists\n";
print "... using top $top_k code lists\n";

print "... $_, $codes_casecount{$_}, $codes_controlscount{$_}\n" foreach @code_keys;




print "\n### Writing data\n";



my $header = "patid,class," . join(",", @code_keys);


foreach my $dementia_type (keys %cases_by_dementia_type) {

    next unless ($dementia_type eq 'all' || $dementia_type eq 'alzheimers' || $dementia_type eq 'vascular');
    print "==> Generating file for $dementia_type\n";

    open my $out, ">", "../data/patients/yearwise/$year/featurified_codes-$dementia_type-top_${top_k}_codes.txt" or die "Can't open ../data/patients/yearwise/$year/featurified_codes-$dementia_type-top_${top_k}_codes.txt: $!\n";
    print $out "$header\n";



    my $i = 0;
    my %printedpatients;
    #foreach my $pat (keys %cases) {
    foreach my $pat (@{$cases_by_dementia_type{$dementia_type}}) {
        next unless $cases_list{$pat};
        if ($dementia_type ne 'all') {
            next if $excluded_patients{$pat}; # for specific subtypes, exclude multi-type cases
        }
        # exclude patients w/o matching control
        # next unless $controls{$patient_controls_map{$pat}};
        # ... did this above already

        my $datapoint = "";
        $datapoint .= $pat;
        $datapoint .= ", 1"; # class 1 : cases
        my $codecount = 0;
        foreach my $mc (@code_keys) {
            my $val = ($patients{$pat}{codes}{$mc}) ? 1 : 0;   # binary features
            #my $val = $patients{$pat}{codes}{$mc} || 0;         # non binary
            $datapoint .= ", $val";
            $codecount++ if $val; # count how many codes this patient has assigned
        }

        #    foreach my $pc (@prodcode_keys) {
        #       my $val = $patients{$pat}{prodcodes}{$pc} || 0;
        #       print $out ", $val";
        #    }
        #
        #next unless $codecount > 0;  # uncomment to exclude zero-code patients
        $i++;
        $printedpatients{$pat}++;
        print $out "$datapoint\n";
    }

    my $stats = &get_statistics(\%printedpatients);
    my $gender_print = "";
    $gender_print .= "$_: $stats->{genders}{$_}, " foreach sort { $a <=> $b } keys %{$stats->{genders}};
    chop $gender_print;
    chop $gender_print;
    print "... $i cases included ( features: [$stats->{case_features}{min} .. $stats->{case_features}{median} .. $stats->{case_features}{max}]; ages: [$stats->{ages}{min} .. $stats->{ages}{median} .. $stats->{ages}{max}]; gender: {$gender_print}\n";

    $i = 0;
    foreach my $pat (keys %controls_list) { # change this to keys %controls to exclude zero-code controls
        #next unless $controls{$pat};
        next unless $printedpatients{$controls_patient_map{$pat}};

        my $datapoint = "";
        $datapoint .= $pat;
        $datapoint .= ", 0"; # class 0 : controls
        my $codecount = 0;
        foreach my $mc (@code_keys) {
            my $val = ($patients{$pat}{codes}{$mc}) ? 1 : 0;   # binary
            #my $val = $patients{$pat}{codes}{$mc} || 0;         # non binary
            $datapoint .= ", $val";
            $codecount++ if $val; # count how many codes this patient has assigned
        }

        #    foreach my $pc (@prodcode_keys) {
        #       my $val = $patients{$pat}{prodcodes}{$pc} || 0;
        #       print $out ", $val";
        #    }
        #
        #next unless $codecount > 5;
        #$printedpatients{$pat}++;
        $i++;
        print $out "$datapoint\n";
    }
    #print "... $i controls included\n";
    print "... $i controls included ( features: [$stats->{control_features}{min} .. $stats->{control_features}{median} .. $stats->{control_features}{max}];\n";

    close $out or die "Can't close featurified_codes-$dementia_type-top_${top_k}_codes.txt: $!\n";

}



sub get_statistics {
    my $incases = shift;

    my %gender = ( cases => { }, controls => { } );
    my %featurecounts = ( cases => [], controls => [] );
    my %agecounts = ( cases => [], controls => [] );

    foreach my $case (keys %$incases) {
        my $case_gender = $genders{$case};
        my $case_age    = $ages{$case};
        my $case_features = scalar keys %{$cases{$case}{codes}};

        $gender{cases}{$case_gender}++;
        push @{$agecounts{cases}}, $case_age;
        push @{$featurecounts{cases}}, $case_features;

        my $control = $patient_controls_map{$case};
        my $control_gender   = $genders{$control};
        my $control_age      = $ages{$case};
        my $control_features = scalar keys %{$controls{$control}{codes}};

        $gender{controls}{$control_gender}++;
        push @{$agecounts{controls}}, $control_age;
        push @{$featurecounts{controls}}, $control_features;
    }

    my @case_a = sort { $a <=> $b } @{$agecounts{cases}};
    my $ages = {
        median  => $case_a[int(scalar @case_a / 2)],
        max     => pop @case_a,
        min     => shift @case_a
    };
    my @case_f = sort { $a <=> $b } @{$featurecounts{cases}};
    my $case_features = {
        median  => $case_f[int(scalar @case_f / 2)],
        max     => pop @case_f,
        min     => shift @case_f
    };
    my @control_f = sort { $a <=> $b } @{$featurecounts{controls}};
    my $control_features = {
        median  => $control_f[int(scalar @control_f / 2)],
        max     => pop @control_f,
        min     => shift @control_f
    };

    return { ages => $ages, case_features => $case_features, control_features => $control_features, genders => $gender{cases} };


}




sub write_stats {

    open my $medstats, ">", "medcode_stats.txt" or die "Can't open medcode_stats.txt: $!\n";
    print $medstats "medcode, occurrences, patients\n";
    print $medstats "$_, $codes{$_}, $codes_patientcount{$_}\n" foreach keys %codes;
    close $medstats or die "Can't close medstats: $!\n";

    open my $prodstats, ">", "prodcode_stats.txt" or die "Can't open prodcode_stats.txt: $!\n";
    print $prodstats "prodcode, occurrences, patients\n";
    print $prodstats "$_, $codes{$_}, $codes_patientcount{$_}\n" foreach keys %codes;
    close $prodstats or die "Can't close medstats: $!\n";

}
