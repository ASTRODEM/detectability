#!/bin/bash

set -x 

./vectorize_patients.pl year1 > ../data/patients/yearwise/year1/featurization_log.txt 
./vectorize_patients.pl year2 > ../data/patients/yearwise/year2/featurization_log.txt 
./vectorize_patients.pl year3 > ../data/patients/yearwise/year3/featurization_log.txt 
./vectorize_patients.pl year4 > ../data/patients/yearwise/year4/featurization_log.txt 
./vectorize_patients.pl year5 > ../data/patients/yearwise/year5/featurization_log.txt 


cd ../data/patients/yearwise 

./forrest4type.pl  all 
./forrest4type.pl  alzheimers 
# ./forrest4type.pl  others 
# /forrest4type.pl  unspecified 
./forrest4type.pl  vascular 


