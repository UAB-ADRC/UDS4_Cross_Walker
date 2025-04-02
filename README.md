# UDS4 Crosswalk - Crosswalk Parser

## Authors
- [Chad Murchison](https://github.com/cfmurch), UAB ADRC
- [Jai Nagidi](https://github.com/jnagidi), UAB ADRC

## License
This project is licensed under the MIT License - see [LICENSE](LICENSE.md) for details

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

```bash
python UDS_Crosswalk_Parser.py <path to UDS3 CSV> <path to folder of JSON files> <path to UDS4 order txt>
```

```bash
Rscript UDS_Crosswalk_Parser.R <path to UDS3 CSV> <path to folder of JSON files> <path to UDS4 order txt>
```
  
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
Step 1: Prepare Your UDS3, JSON Crosswalk, and Variable order files. Make note of locations.

Step 2a: Run the Script from the command line
Navigate to the folder where the desired script file is located and enter either the Python or R variant as described above

Step 2b: Run the script interactively
The .py or .R file can be opened within an IDE such as Jupyter Notebook or RStudio and run interactively.  If this step is done, folder paths will need to be provided by the user within the scripts.  Sections for these variables can be found at the beginning of the "Main Process" section of each parser.

The script will apply the crosswalk parsing migrating all valid variables from UDS3 to UDS4.

Step 3: **Check the Output**: 
After running the script, the The script will apply the cross walk to the UDS3 data and generate a new UDS4 data file called `uds4_redcap_data.csv`.

## Troubleshooting
If you encounter any issues, ensure that you are using the correct Python version and have installed all dependencies from the requirements.txt file.<br>
Be sure JSON files only exist within the JSON folder path provided.
Make certain the ordered variable list for UDS4 exists and contains all listed variables.  Again, use the `UDS4Data_ColumnOrder.txt` file provided with this repository as desired.
