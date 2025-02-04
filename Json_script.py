import os
import pandas as pd
import json
import re
from datetime import datetime

# Define the folder containing the files
folder_path = r'C:\Users\jaiga\Downloads\Crosswalks'  # Replace with your folder path

def json_serializer(obj):
    if isinstance(obj, datetime):
        return obj.isoformat()  # Converts datetime to an ISO 8601 string
    raise TypeError(f"Type {type(obj)} not serializable")
    
def clean_text(obj):
    """ Recursively clean text fields in JSON structure. """
    if isinstance(obj, dict):
        return {k: clean_text(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [clean_text(i) for i in obj]
    elif isinstance(obj, str):
        return obj.replace('_x000D_', '').strip()  # Remove unwanted characters
    return obj

# Function to classify variables
def classify_variable(df):
    def classify(group):
        if group['uds4 data element'].str.endswith('X').all() and group['uds3 data element'].str.endswith('X').all() and group['data type change'].eq('No').all():
            return 'direct'
        if group['special mapping'].isin(['Structured', 'Merging', 'Merging; Calculated field']).any():
            return 'sp'
        elif group['special mapping'].isin(['Calculated field']).any():
            return 'cc'
        elif group['special mapping'].isna().all():
            if group['conformity change'].eq('Yes').any() or group['data type change'].eq('Yes').any() or group['change in form'].eq('Yes').any():
                return 'cc'
            elif group['uds4 data element'].iloc[0] == group['uds3 data element'].iloc[0]:
                return 'direct'
            else:
                return 'cc'
        else:
            return 'complex'
            
    classifications = df.groupby('uds4 data element', group_keys=False).apply(classify)
    df = df.merge(classifications.rename('class'), on='uds4 data element', how='left')
    return df

# Function to categorize variables
def categorize_variables(df):
    direct_mappings = []
    conditional_consistency_mappings = []
    structured_transformation_mappings = []
    complex_mappings = []

    for (uds3_var, uds4_var), group in df.groupby(['uds3 data element', 'uds4 data element']):
        variable_class = group['class'].iloc[0]
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
            for _, row in group.iterrows()
        ]

        mapping_entry = {
            "UDS3_variable": uds3_var,
            "UDS4_variable": uds4_var,
            "crosswalk_mappings": crosswalk_mappings,
        }

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

    all_mappings = {
        "Direct_Mappings": direct_mappings,
        "Conditional_Consistency": conditional_consistency_mappings,
        "Structured_Transformations": structured_transformation_mappings,
        "High_Complexity": complex_mappings,
    }
    return all_mappings

# Iterate over each file in the folder
for file_name in os.listdir(folder_path):
    if file_name.endswith('.xlsx'):  # Process only Excel files
        file_path = os.path.join(folder_path, file_name)
        print(f"Processing file: {file_name}")

        # Load data from the Excel file
        uds3_rdcp = pd.read_excel(file_path, sheet_name=2, header=1)
        uds4_rdcp = pd.read_excel(file_path, sheet_name=3, header=1)
        df = pd.read_excel(file_path, sheet_name=5, header=1)

        # Clean and rename columns
        df.columns = df.columns.str.lower()
        uds4_rdcp.columns = uds4_rdcp.columns.str.lower()
        uds3_rdcp.columns = uds3_rdcp.columns.str.lower()
        uds4_rdcp = uds4_rdcp.iloc[:, :12]

        # Merge data
        test = pd.merge(df, uds4_rdcp, on='uds4 data element')

        # Classify and categorize variables
        result = classify_variable(test)
        result['uds3 value'] = result['uds3 value'].where(result['uds3 value'].notnull(), None)
        result['uds4 value'] = result['uds4 value'].where(result['uds4 value'].notnull(), None)
        result['notes and discussion points'] = result['notes and discussion points'].fillna("NA")
        result['reversible to uds3'] = result['reversible to uds3'].fillna("NA")
        result.loc[result['uds4 value'] == "<BLANK>", 'uds4 value'] = ""

        all_mappings = categorize_variables(result)
        all_mappings = clean_text(all_mappings)
        all_mappings = json.dumps(all_mappings, ensure_ascii=False, indent=4, default=json_serializer)

        # Save output to JSON
        output_path = os.path.join(folder_path, f"{os.path.splitext(file_name)[0]}_mappings.json")
        with open(output_path, 'w', encoding='utf-8') as json_file:
            json_file.write(all_mappings)
            #json.dump(all_mappings, json_file, ensure_ascii=False, indent=4,default=json_serializer)

        print(f"Processed and saved: {output_path}")
