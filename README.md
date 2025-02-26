# JSON Script for Data Processing

## Authors
- [Chad Murchison](https://github.com/cfmurch), UAB ADRC
- [Jai Nagidi](https://github.com/jnagidi), UAB ADRC

## License
This project is licensed under the MIT License - see [LICENSE](LICENSE) for details

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

<br>
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
If no folder path is provided, this will default to './Crosswalk' located in folder from which the UDS_JSON_Maker.py is run.  For convenience, a collection of crosswalk sheets are provided here.

The script will process all Excel files in the provided folder and generate:
- A JSON file for each Excel file, named <original_filename>_mappings.json which can then be used for a programmatic crosswalk.

Step 3: **Check the Output**: 
After running the script, the generated JSON files are in the same folder as the Excel files.

**Note**: Ensure the Excel files contain the required input in the UDS3/4 REDCap dictionary sheets and Template Mappings sheets.  Note, new UDS4 forms have no mappings rules thus some crosswalk files for forms like A1a, A4a, etc., do not have the 'Template Mappings REDCap' sheet . Be sure to remove or delete those Excel crosswalk files from the folder before running the script.

## Troubleshooting
If you encounter any issues, ensure that you are using the correct Python version and have installed all dependencies from the requirements.txt file.<br>
Make sure that the folder path provided contains only .xlsx files that match the required format described in the Crosswalk section above.
