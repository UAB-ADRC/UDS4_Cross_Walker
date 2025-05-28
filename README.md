# UDS4 Crosswalk

## Authors
- [Chad Murchison](https://github.com/cfmurch), UAB ADRC
- [Jai Nagidi](https://github.com/jnagidi), UAB ADRC

## License
This project is licensed under the MIT License - see [LICENSE](LICENSE.md) for details

# Part 1 - Generation of JSON Files

## UDS_JSON_Maker.py
This is the primary Python script which processes Excel files in a given folder (given as a command line argument), process the relevant mapping rules, and saves the output as JSON.<br>
<br>
The goal of the JSON files is to help programmatically apply the conversion of data elements between UDS3 and UDS4 formats.  An emphasis is given on UDS3 -> UDS4 although reversible rules are also flagged.

## Crosswalk Folder
This folder contains properly formatted Excel workbooks used by the Python script to generate the JSON files containing the following sheets:

  - UDS3_4 Tables Data Dictionary: Data dictionary for the three UDS variable tables and the change indicators between UDS3 and UDS4
  - XX UDS3 DED: Form specific table for UDS3 built from the Data Element Dictionary for UDS3, included for reference
  - XX UDS3 REDCap: Form specific table for UDS3 built from the original Kansas ADRC REDCap data dictionary
  - XX UDS4 REDCap: Form specific table for UDS4
    - Note, Template Mappings are oriented using REDCap-to-REDCap conventions
  - Mappings Data Dictionary: Data dictionary for the template mappings to migrate UDS variables from version 3 to version 4
  - Template Mappings REDCap: The sheet containing all rules processed and stored into JSON format.  Modifications to rules for a specific ADRC can be applied here.
  - XX Mappings - ADRC Decisions: Ambiguous rules that should be vetted by the ADRC.  Options are flagged as ADRC Decision_A and ADRC Decision_B where applicable to indicate rule sets.

**Rules in 'Mappings - ADRC Decisions' must be vetted and added to the 'Template Mappings REDCap' sheet before compiling JSON files!**

## Modification of Template Mappings
Template mappings can be modified as needed to reflect your specific instance of UDS3 and UDS4.  Structure on the Template Mappings REDCap should remain consistent, simply update the entries in the 'UDS3 value' and 'UDS4 value' columns.<br>
<br>
As described, be sure to select rules from the ADRC Decision sheet and add them to the Template Mappings prior to generating JSON files.

## Application

### Requirements
Before you run the script, make sure you have Python installed on your system along with the required libraries. To install the necessary dependencies, follow these steps:

1. Install Python (if not already installed):
   - Download Python: https://www.python.org/downloads/
   - Ensure that Python and `pip` (Python's package installer) are added to your system's PATH.

2. Install required libraries from the command line using pip (or controlling environment e.g. conda)
   ```bash
   pip install -r requirements.txt
    ```

### How to Use the Script
Step 1: Prepare Your Files
Ensure that your Excel files are located in a folder on your computer. Default

Step 2: Run the Script
To run the script, open your terminal or command prompt and navigate to the folder where the script is located. Run the following command, replacing <folder_path> with the path to the folder containing your Excel files if needed:
 ```bash
python UDS_JSON_Maker.py <folder_path>
 ```
For example:
 ```bash
python UDS_JSON_Maker.py C:/Users/YourUsername/Downloads/crosswalks
 ```
___If no folder path is provided, this will default to './Crosswalk' located in folder from which the UDS_JSON_Maker.py is run.  For convenience, a collection of crosswalk sheets are provided here.___

The script will process all Excel files in the provided folder and generate:
- A JSON file for each Excel file, named <original_filename>_mappings.json which can then be used for a programmatic crosswalk.

Step 3: **Check the Output**: 
After running the script, the generated JSON files are in the same folder as the Excel files.

**Note**: Ensure the Excel files contain the required input in the UDS3/4 REDCap dictionary sheets and Template Mappings sheets.  Note, new UDS4 forms have no mappings rules thus some crosswalk files for forms like A1a, A4a, etc., do not have the 'Template Mappings REDCap' sheet . Be sure to remove or delete those Excel crosswalk files from the folder before running the script.

## Troubleshooting
If you encounter any issues, ensure that you are using the correct Python version and have installed all dependencies from the requirements.txt file.<br>
Make sure that the folder path provided contains only .xlsx files that match the required format described in the Crosswalk section above.

# Part 2 - Crosswlk Parser

## Overview
This script is designed to be used in conjunction with a collection of JSON-based crosswalk rules to migrate UDS3 data to UDS4 data.  It is the final step in the UDS3-UDS4 Crosswalk process.  Three constituent pieces are required:
  - UDS3 source data csv file
  - At least one JSON Crosswalk file
  - A file of UDS4 Data Elements used for re-ordering
Both Python and R versions of the Crosswalk Parser exist.

__Note a column order text file is provided with this repository and can be used with this Parser.  This matches the Data Element Dictionary order provided by NACC.  The file name is `UDS4Data_ColumnOrder.txt` found within this parser's main folder.__

## Scope
This Crosswalk Parser is designed to work with csv formatted data files e.g. those from REDCap export.  It has been validated for mapping of levels (i.e. the numeric representation of responses) although options for label mapping are a potential modification the authors are considering.

## JSON Files
For details on the generation of JSON crosswalk mapping files, please see the `UDS4 Crosswalk - JSON Maker` repository.  These scripts presume appropriate JSON files have already been generated.  They do not need have been generated from the JSON Maker but a similar output is expected.

## UDS_Crosswalk_Parser.py / UDS_Crosswalk_Parser.R
These are the principal processing scripts which take in an appropriately formatted file of UDS3 data, a folder of the JSON files developed by the JSON maker, and a listing of the UDS4 variables in a preferred order.  The Crosswalk Parser then applies the JSON rules in order to migrate all UDS3 data to their nearest UDS4 variants where they exist.  UDS3 data which do not have a JSON mapping rule (i.e. a nearest UDS4 neighbor) are excluded and will not be returned.

## Arguments, Folders, and Required Files
Both `UDS_Crosswalk_Parser.py` and `UDS_Crosswalk_Parser.R` are designed to be run from the command line using either of the following:

### 1. Paths as arguments from the command line

```bash
python UDS_Crosswalk_Parser.py <path to UDS3 CSV> <path to folder of JSON files> <path to UDS4 order txt>
```

```bash
Rscript UDS_Crosswalk_Parser.R <path to UDS3 CSV> <path to folder of JSON files> <path to UDS4 order txt>
```

### 2. Interactive selection of files and folders

If the OS support GUI based folder selection, the scripts can also be run from the command line without arguments.  The system will then prompt the user to select (1) the UDS3 CSV, (2) the folder location of the JSON files, and (3) the text file of UDS4 variables for ordering.

### 3. Running scripts directly from IDE environment

The two scripts can also be run directly from within a Jupyter notebook or Rstudio environment.  Be sure to initialize the string paths to the files / folders within the Main Process sections as needed.


## Application

### Requirements - Python
Before you run the script, make sure you have Python installed on your system along with the required libraries. To install the necessary dependencies, follow these steps:

1. Install Python (if not already installed):
   - Download Python: https://www.python.org/downloads/
   - Ensure that Python and `pip` (Python's package installer) are added to your system's PATH environmental variable

2. Install required libraries from the command line using pip (or controlling environment e.g. conda)
   ```bash
   pip install -r requirements.txt
    ```
    
### Requirements - R
1. Install R (if not already installed)
    - Download R: https://cran.r-project.org/
    - Ensure that R is added to your system's PATH environmental variable

2. Necessary packages will be evaluated and downloaded automatically when `UDS_Crosswalk_Parser.R` is run using primary repository (default CRAN)


### How to Use the Script
Step 1: Prepare your UDS3, JSON Crosswalk, and Variable order files. Make note of locations.

Step 2a: Run the Script from the command line
Navigate to the folder where the desired script file is located and enter either the Python or R variant as described above

Step 2b: Run the script interactively
The .py or .R file can be opened within an IDE such as Jupyter Notebook or RStudio and run interactively.  If this step is done, folder paths will need to be provided by the user within the scripts.  Sections for these variables can be found at the beginning of the "Main Process" section of each parser.

The script will apply the crosswalk parsing migrating all valid variables from UDS3 to UDS4.

Step 3: **Check the Output**: 
After running the script and applying the cross walk to the UDS3 data, a new UDS4 data file will be generated called `uds4_redcap_data.csv`.

## Troubleshooting
If you encounter any issues, ensure that you are using the correct R or Python version and have installed all dependencies as required.<br>
Be sure JSON files only exist within the JSON folder path provided.
Make certain the ordered variable list for UDS4 exists and contains all listed variables.  Again, use the `UDS4Data_ColumnOrder.txt` file provided with this repository as desired.


# Part 3 - Dictionary Comparison

## Overview
This script compares the content of two REDCap dictionaries for discrepancies in their field.  Although developed for UDS4 comparisons (e.g. between a local ADRC's version and an update from NACC), it could be applied to any two dictionaries with matched variables.  Three constituent pieces are required:
  - A prior version of a REDCap dictionary 
  - A new iteration of the REDCap dictionary 
  - A curated file listing a specific set of variables for comparison

__Note a curated file is provided with this repository and can be used with this Comparison script.  It matches the Data Element Dictionary order provided by NACC (May 2025).  The file name is `UDS4Data_ColumnOrder.txt` found within this parser's main folder.__

## Scope
This Crosswalk Parser is designed to work with a csv-based data dictionary, specifically from a REDCap export.  While developed for UDS4, this script could be used for any version comparisons of a dictionary.

After the comparison is completed, an Excel workbook is generated which can be used to update local REDCap dictionaries or Crosswalk dictionaries as the user sees fit.

## UDS_dictionary_update.R
This is the primary script which takes in a prior and updated pair of REDCap dictionaries and an optional curated list of variables to explicitly compare.  The comparison tool identifies variables which only appear in the prior or new dictionary as well as any dictionary field deviations for any matched variables.  After the comparison, an Excel workbook output summarizes all comparisons made for downstream application by the user.

## Arguments, Folders, and Required Files
`UDS_Dictionary_Update.R` is designed to be run from the command line using either of the following:

### 1. Paths as arguments from the command line

```bash
Rscript UDS_Dictionary_Update.R <path to prior dictionary CSV> <path to updated dictionary CSV> <path to curated variable list txt>
```

### 2. Interactive selection of files and folders

If the OS support GUI based folder selection, the scripts can also be run from the command line without arguments.  The system will then prompt the user to select (1) the prior REDCap dictionary, (2) the updated REDCap dictionary, and (3) the curated list of variables for comparison.

### 3. Running scripts directly from IDE environment

The script can also be run directly from within an Rstudio environment.  Be sure to initialize the string paths to the files / folders within the Main Process sections as needed.


## Application

### Requirements - R
1. Install R (if not already installed)
    - Download R: https://cran.r-project.org/
    - Ensure that R is added to your system's PATH environmental variable

2. Necessary packages will be evaluated and downloaded automatically when `UDS_Dictionary_Update.R` is run using primary repository (default CRAN)

### How to Use the Script
Step 1: Prepare your prior dictionary, new dictionary, and curated variable list files. Make note of locations.

Step 2a: Run the Script from the command line
Navigate to the folder where the desired script file is located and enter either the BASH commands as described above

Step 2b: Run the script interactively
The .R file can be opened within the RStudio IDE and run interactively.  If this step is done, folder paths will need to be provided by the user within the scripts.  Sections for these variables can be found at the beginning of the "Main Process" section.

The script will compare the two dictionaries as described before generating an Excel workbook.

Step 3: **Check the Output**: 
After running the script, an Excel workbook output file will be generated titled "UDS_Dictionary_Comparison_YYYYMMDD.xlsx" using today's date.  It will have the following tabs:
    - 'Unmatched - Prior' - entries found exclusively in the __prior__ dictionary
    - 'Unmatched - New' - entries found solely in the __new__ dictionary
    - 'Prior Entries' - entries from the prior dictionary where field discrepancies were found
    - 'New Entries' - entries for those same variables from the new dictionary
    - 'Field Differences' - a breakdown for each variable listing which dictionary fields differed and what the field entries were for the prior and new dictionary
Note: the 'Prior Entries' and 'New Entries' tab will include a new "Index" column which lists the absolute position of the variable in its respective dictionary

## Modifying definitions
A series of variables can be modified as desired within `UDS_Dictionary_Update.R`
    - `var_col` - The column containing the variable name in the dictionary, defaults to "Variable / Field Name"
    - `ignored_fields` - Any column names the user wishes to not be compared, defaults solely the "Index" column generated during processing but other REDCap fields can be added to the vector as desired
    - `to_ignore` - Any specific variables the user wishes to ignore, set to NULL by default but can be used in tandem with the curated list
    - `ignored_regex` - A regular expression which can be applied during comparison to flag a field pairing as being the same even if a difference is observed; default is set to ignore any instance of "[current-instance]==1" as a practical example


## Troubleshooting
If you encounter any issues, ensure that you are using the correct Python version and have installed all dependencies from the requirements.txt file.<br>
Although columns are checked between the dictionaries, make sure they match appropriately for ease of application
Make certain the ordered variable list for UDS4 exists and contains all listed variables.  Again, use the `UDS4Data_ColumnOrder.txt` file provided with this repository as desired.
