import os,sys
import pandas as pd
import json
import re
from datetime import datetime


# Define the folder containing the files, default to ./Crosswalk
if len(sys.argv) > 1 and sys.argv[1].strip():
    folder_path = sys.argv[1]  # Use the provided argument
else:
    folder_path = "./Crosswalk" 


## FUNCTION DEFINITIONS

# Converts datetime to an ISO 8601 string
def json_serializer(obj):
    if isinstance(obj, datetime):
        return obj.isoformat()  
    raise TypeError(f"Type {type(obj)} not serializable")


# Clean text fields in the JSON structres
def clean_text(obj):
    " Recursively cleaning text fields in JSON structure. "
    if isinstance(obj, dict):
        return {k: clean_text(v) for k, v in obj.items()}  # Key-value cleaning in a dictionary
    elif isinstance(obj, list):
        return [clean_text(i) for i in obj]  # Text cleaning for single list items
    elif isinstance(obj, str):
        return obj.replace('_x000D_', '').strip()  # Remove unwanted characters and whitespace
    return obj


# Classification of the columns in the template mappings for JSON processing
def classify_variable(df):
    def classify(group):
      # Direct mapping in UDS4/UDS3 column names ending with "X", with no change in their data types(e.g. free text fields like primlangx)
        if group['uds4 data element'].str.endswith('X').all() and group['uds3 data element'].str.endswith('X').all() and group['data type change'].eq('No').all():
            return 'direct'
      # Special structured mappings and mergings
        if group['special mapping'].isin(['Structured', 'Merging', 'Merging; Calculated field']).any():
            return 'sp'
      # Conditional consistency for non-mergings on calculated fields
        elif group['special mapping'].isin(['Calculated field']).any():
            return 'cc'
      # Special mappings catches using conformity
        elif group['special mapping'].isna().all():
          # If conformity or data type change exists, use conditional consistency
            if group['conformity change'].eq('Yes').any() or group['data type change'].eq('Yes').any() or group['change in form'].eq('Yes').any():
                return 'cc'
          # If conformity change not in place for special mapping and the column names are the same in UDS4/UDS3, return direct mappings
            elif group['uds4 data element'].iloc[0] == group['uds3 data element'].iloc[0]:
                return 'direct'
            else:
                return 'cc'
      # In all other cases, consider it as complex
        else:
            return 'complex'

    # Organize by UDS4 name, apply the classification grouping, and annotate the dataframe with new 'class' column
    # Doing hard selection of column names to make sure the grouping column gets passed in pandas 3+
    all_columns = df.columns.tolist()
    classifications = df.groupby('uds4 data element')[all_columns].apply(classify)
    df = df.merge(classifications.rename('class'), on='uds4 data element', how='left')
    return df


# Function to categorize variables
def categorize_variables(df):
  # Initialize arrays by classification type
    direct_mappings = []
    conditional_consistency_mappings = []
    structured_transformation_mappings = []
    complex_mappings = []
    
    # For each UDS3 and UDS4 variable pair (allows for merging)
    for (uds3_var, uds4_var), group in df.groupby(['uds3 data element', 'uds4 data element']):
      
      # Check class of the mapping 
        variable_class = group['class'].iloc[0]
      # Build common single mapping elements (UDS3 and UDS4 value, reversible from 3 to 4, any notes)
        crosswalk_mappings = [
            {
                "mapping_type": row["mapping type"],
                "mappings": [
                    {
                        "UDS3_value": row["uds3 value"],
                        "UDS4_value": row["uds4 value"],
                        "reversible": row["reversible to uds3"],
                        "note": row.get("notes and discussion points", ""),
                    }
                ],
            }
          # Use iterrows to build and append this dictionary for each row
            for _, row in group.iterrows()
        ]

      # Nest the mapping dictionary within the UDS3/UDS4 pairing
        mapping_entry = {
            "UDS3_variable": uds3_var,
            "UDS4_variable": uds4_var,
            "crosswalk_mappings": crosswalk_mappings,
        }

      # Organize the built JSON pairing by the four classifications
        if variable_class == "sp":
            structured_transformation_mappings.append(mapping_entry)
        elif variable_class == "cc":
            conditional_consistency_mappings.append(mapping_entry)
        elif variable_class == "complex":
            complex_mappings.append(mapping_entry)
        elif variable_class == "direct":
                direct_mappings.append({
                "UDS3_variable": uds3_var,
                "UDS4_variable": uds4_var,
                "crosswalk_remappings": crosswalk_mappings,
            })
            
  # Final aggregation
    all_mappings = {
        "Direct_Mappings": direct_mappings,
        "Conditional_Consistency": conditional_consistency_mappings,
        "Structured_Transformations": structured_transformation_mappings,
        "High_Complexity": complex_mappings,
    }
    return all_mappings



## PRIMARY LOOP

# Iterate over each UDS4 file in the folder from folder_path
for file_name in os.listdir(folder_path):
  
  # Process file name
    if file_name.endswith('.xlsx'):  # Process only Excel files
        file_path = os.path.join(folder_path, file_name)
        print(f"Processing file: {file_name}")

      # Load data from the Excel file according to sheet
      # Regexes for the table specific
        uds3_pattern = re.compile(r'.*? UDS3 REDCap')
        uds4_pattern = re.compile(r'.*? UDS4 REDCap')
      # Get the sheet names
        excel_file = pd.ExcelFile(file_path)
        sheet_names = excel_file.sheet_names
      # Get the regex matches for UDS3 and UDS4 dictionaries
        uds3_sheet = [name for name in sheet_names if uds3_pattern.match(name)][0]
        uds4_sheet = [name for name in sheet_names if uds4_pattern.match(name)][0]
      # Read in the dictionaries
        uds3_rdcp = pd.read_excel(file_path, sheet_name=uds3_sheet, header=1)  # UDS3 REDCap dictionary
        uds4_rdcp = pd.read_excel(file_path, sheet_name=uds4_sheet, header=1)  # UDS4 REDCap dictionary
      # Simple hard name call for the templated mapping rules for processing
        df = pd.read_excel(file_path, sheet_name='Template Mappings REDCap', header=1)

      # Clean, lower, and rename columns
        df.columns = df.columns.str.lower()
        uds4_rdcp.columns = uds4_rdcp.columns.str.lower()
        uds3_rdcp.columns = uds3_rdcp.columns.str.lower()
        uds4_rdcp = uds4_rdcp.iloc[:, :12]
        uds4_rdcp.rename(columns={"uds4 data element name": "uds4 data element"}, inplace=True)

      # Merge template mappings with UDS4 dictionary
        test = pd.merge(df, uds4_rdcp, on='uds4 data element')

      # Apply classification and categorization of variable pairings
        result = classify_variable(test)
      # Ignore any variables that are missing a UDS3/UDS4 neighbor
        result['uds3 value'] = result['uds3 value'].where(result['uds3 value'].notnull(), None)
        result['uds4 value'] = result['uds4 value'].where(result['uds4 value'].notnull(), None)
      # Fill in notes and reversible fields with NA as needed
        result['notes and discussion points'] = result['notes and discussion points'].fillna("NA")
        result['reversible to uds3'] = result['reversible to uds3'].fillna("NA")
      # Recast <BLANK> REDCap LABELS as empty strings
        result.loc[result['uds4 value'] == "<BLANK>", 'uds4 value'] = ""

      # Apply the primary categorization and JSON-esque dictionary building function
        all_mappings = categorize_variables(result)
      # Clean text as described and format as JSON files
        all_mappings = clean_text(all_mappings)
        all_mappings = json.dumps(all_mappings, ensure_ascii=False, indent=4,default=json_serializer)

      # Save output to JSON
        output_path = os.path.join(folder_path, f"{os.path.splitext(file_name)[0]}_mappings.json")
        with open(output_path, 'w', encoding='utf-8') as json_file:
            json_file.write(all_mappings)
      # Sanity tracker
        print(f"Processed and saved: {output_path}")
