The scripts in this directory provide the following functionality: 

* filtertoallyearpatients.pl : script used to filter patient data in individual years to those patients with full five years of data (some patients did not have five year records; these were excluded from the analysis alltogether) 

* forrest4type.pl : script to prepare and execute random_forest.py on a given patient stratum for all years under analysis.

* random_forest.py : train and test one or more random forest classifyers on data from one or more input files (one classifyer each) and create a single plot showing the AUC of each classifyer. 

* vectorize_all_years.sh : pipeline script to first call vectorize_patients.pl for all 5 years under analysis and then call forrest4type.pl for each of a selected set of different types of dementia
* vectorize_patients.pl : preprocess, cleanse, filter and stratify patients, map documented codes to code lists and generate feature represenations; reads data from files exported from CPRD in a given directory (e.g., representing patients within a given year of analysis); outputs to the given directory files with the generated feature representations of the patients for each stratum (Alzheimers, vascular, all)
