import re
import json
import sys, os
import rdata
import warnings
import pandas as pd
import numpy as np
import io
from bs4 import BeautifulSoup

# Ignore all warnings
warnings.filterwarnings("ignore")


if len(sys.argv) > 3:
	# Inputs -- 1. UDS3 Recap Data path, 2.Json Crosswalk folder path, 3. UDS3_Data_Elements_list
    uds3_data_path, json_folder_path, data_order_path = sys.argv[1],sys.argv[2],sys.argv[3]
elif sys.stdin and sys.stdin.isatty(): 
  print("Running interactively, be sure to update paths in Main Process")
else:
    print("Please Provide the UDS3_data, Json Crosswalk Folder and Data Order paths")
    exit()


def load_json_files(directory):
    json_files = [f for f in os.listdir(directory) if f.endswith('.json')]
    mapping_data = {}
    
    for json_file in json_files:
        with open(os.path.join(directory, json_file), 'r',encoding='utf-8') as f:
            mapping_data[json_file] = json.load(f)
    
    return mapping_data


def process_repeating_variables(uds3_var, uds4_var, uds3_df, uds4_df, response_map=None):
    kid_sib_pattern = re.compile(r'(kid|sib)')
    match = kid_sib_pattern.search(uds3_var)
    
    if not match:
        return
    
    word = match.group(1)
    rng = 15 if word == 'kid' else 20

    # Clean up base variable names
    base_var = uds3_var.replace(word, '').replace('#', '')
    base_var1 = uds4_var.replace(word, '').replace('#', '')

    for i in range(1, rng + 1):
        new_uds3_col = f"{word}{i}{base_var}"
        new_uds4_col = f"{word}{i}{base_var1}"

        if new_uds3_col not in uds3_df.columns:
            continue

        if response_map:
            # Create a mapping function to speed up value replacement
            col_values = uds3_df[new_uds3_col].astype(str)
            mapped_values = col_values.map(lambda val: response_map.get(val, val))

            # Handle unmatched values
            if not new_uds4_col.endswith("tpr"):
                mapped_values[~mapped_values.isin(response_map.values())] = col_values

            uds4_df[new_uds4_col] = mapped_values
        else:
            # Directly copy the values if no response map
            uds4_df[new_uds4_col] = uds3_df[new_uds3_col]


def process_mappings(mapping_data, mapping_type):
    """
    Process mappings from UDS3 to UDS4 based on the specified mapping type.

    Args:
        mapping_data (dict): The dictionary containing mapping configurations.
        mapping_type (str): The type of mapping to process (e.g., 'Direct_Mappings').
    """
    # Iterate through each mapping entry for the given mapping type
    for mapping in mapping_data.get(mapping_type, []):
        
        # Extract and normalize UDS3 and UDS4 variable names to lowercase
        uds3_var = mapping["UDS3_variable"].lower()
        uds4_var = mapping["UDS4_variable"].lower()

        # Resolve UDS3 variable names using a data dictionary, if available
        uds3_var = data_dict.get(uds3_var, uds3_var)
        
        # Initialize structured mappings list
        structured_mappings = []

        # Handle different mapping types
        if mapping_type == 'Direct_Mappings':
            # Extract response level and conformity mappings for direct mappings
            response_levels = [m for m in mapping["crosswalk_remappings"] if m["mapping_type"] == "Response LEVELS"]
            conformity = [m for m in mapping["crosswalk_remappings"] if m["mapping_type"] == "Conformity"]
        else:
            # Extract response level, conformity, and structured mappings for non-direct mappings
            response_levels = [m for m in mapping["crosswalk_mappings"] if m["mapping_type"] == "Response LEVELS"]
            conformity = [m for m in mapping["crosswalk_mappings"] if m["mapping_type"] == "Conformity"]
            structured_mappings = [m for m in mapping.get("crosswalk_mappings", []) if m["mapping_type"] == "Structured mapping"]
  

        # Special Case: Handling cases where uds3_var has two columns separated by " | " - useful for sheets like A5D2,B1 and B8        # Special Case: Handling cases where uds3_var has two columns separated by " | " - useful for sheets like A5D2,B1 and B8
        if "|" in uds3_var and not structured_mappings:
            
            # Split the uds3_var into two columns based on " | " separator
            uds3_vars = uds3_var.split(" | ")

            # Ensure there are exactly two columns after splitting
            if len(uds3_vars) == 2:
                primary_col, secondary_col = uds3_vars[0], uds3_vars[1]

                # Check if both primary and secondary columns exist in the uds3_df DataFrame
                if primary_col in uds3_df.columns and secondary_col in uds3_df.columns:
                    # Handle both NaN and 'NA' cases
                    mask = uds3_df[primary_col].isnull() | (uds3_df[primary_col] == "NA")
                    # Filling up the missing values in primary_col with secondary_col values
                    uds3_df.loc[mask, primary_col] = uds3_df.loc[mask, secondary_col]
                    
                    # Set uds3_var to primary_col as it will be used for the next steps
                    uds3_var = primary_col

                # If only the primary column exists in uds3_df
                elif primary_col in uds3_df.columns:
                    uds3_var = primary_col  # Use primary_col for further operations

                # If only the secondary column exists in uds3_df
                else:
                    uds3_var = secondary_col  # Use secondary_col for further operations  
              
        
        # Case -1 : Response levels and no conformity
        # This block handles mapping responses when there are response levels, but no conformity flag is set
        if response_levels and not conformity and uds3_var in uds3_df.columns:
            # Create a dictionary mapping each UDS3 value to its corresponding UDS4 value from response_levels
            response_map = {str(item["UDS3_value"]): str(item["UDS4_value"]) 
                            for mapping in response_levels for item in mapping["mappings"]}

            # Iterate through each mapping between UDS3 value and UDS4 value
            for uds3_value, uds4_value in response_map.items():
                # Skip values containing "|" or "grep(" as they are not to be mapped
                if "|" not in uds3_value and "grep(" not in uds3_value:
                    
                    # If the UDS4 variable exists in the UDS4 DataFrame
                    if uds4_var in uds4_df.columns:
                        # Identify rows in UDS4 where the value is missing (NaN)
                        stm = uds4_df[uds4_var].isna()

                        # Map the UDS3 value to the UDS4 value where the UDS4 value is missing
                        uds4_df.loc[stm & (uds3_df[uds3_var].astype(str) == uds3_value), uds4_var] = uds4_value
                    else:
                        # If the UDS4 variable doesn't exist, just map the UDS3 value to the UDS4 variable
                        uds4_df.loc[uds3_df[uds3_var].astype(str) == uds3_value, uds4_var] = uds4_value

        # Check if there are any structured mappings to process
        # case -2: structured mappings i.e, Dates and calculated fields
        elif structured_mappings:
            # Iterate through each structured mapping entry
            for struct_map in structured_mappings:
                for mapping_entry in struct_map["mappings"]:
                    # Extract UDS3 and UDS4 values from the mapping entry
                    uds3_value = mapping_entry["UDS3_value"]
                    uds4_value = mapping_entry["UDS4_value"]

                    # Handling conditional IF-ELSE structured mappings
                    if "IF(" in uds3_value:
                        # Split the UDS3 variables to handle multiple conditions
                        uds3_vars = uds3_var.split(" | ")

                        # Create a dictionary mapping UDS3 values to UDS4 values
                        response_map = {str(item["UDS3_value"]): str(item["UDS4_value"]) 
                                        for mapping in response_levels 
                                        for item in mapping["mappings"]}

                        # Iterate through each UDS3-UDS4 value pair in the response map
                        for uds3_value, uds4_value in response_map.items():

                            # Determine the logical operator used (OR or AND)
                            operator = "|" if "|" in uds3_value else "&"

                            # Split UDS3 values based on the operator to handle multiple conditions
                            values = uds3_value.split(f" {operator} ")

                            # Handle logical OR conditions
                            if operator == "|":
                                condition = False  # Start with False for OR logic

                                for col, val in zip(uds3_vars, values):
                                    # Handle NULL or missing values
                                    if val in ["NA", "None"]:
                                        condition |= uds3_df[col].isna() | (uds3_df[col].astype(str).str.upper().isin(["NA"]))
                                    else:
                                        # Match exact values
                                        condition |= (uds3_df[col].astype(str) == val)

                            # Handle logical AND conditions
                            elif operator == "&":
                                condition = True  # Start with True for AND logic

                                for col, val in zip(uds3_vars, values):
                                    # Handle NULL or missing values
                                    if val in ["NA", "None"]:
                                        condition &= uds3_df[col].isna() | (uds3_df[col].astype(str).str.upper().isin(["NA"]))
                                    else:
                                        # Match exact values
                                        condition &= (uds3_df[col].astype(str) == val)

                            # Apply the transformation by updating the UDS4 dataframe
                            uds4_df.loc[condition, uds4_var] = uds4_value
                        
                    # Identify separator: OR ('|') or AND ('&')
                    if "|" in uds3_value:
                        separator = "|"
                        operator = np.logical_or
                    elif "&" in uds3_value:
                        separator = "&"
                        operator = np.logical_and
                    else:
                        separator = None
                        operator = None

                    # Handling multiple UDS3 variables with OR / AND conditions
                    if separator:
                        uds3_vars = [var.strip() for var in uds3_var.split(f" {separator} ")]
                        uds3_values = [var.strip() for var in uds3_value.split(f" {separator} ")]

                        # Ensure all UDS3 columns exist in the DataFrame
                        if all(col in uds3_df.columns for col in uds3_vars):
            
                            conditions = [(uds3_df[col].astype(str) == val) for col, val in zip(uds3_vars, uds3_values)]
                            # Apply OR or AND depending on the separator
                            if separator == '|':
                                mask = np.logical_or.reduce(conditions)
                            else:
                                mask = np.logical_and.reduce(conditions)

                            # Only update where conditions match
                            if uds4_var in uds4_df.columns:
                                missing_mask = uds4_df[uds4_var].isna()  # Handle missing (NA) values in uds4_df
                                #uds4_df.loc[missing_mask & mask, uds4_var] = uds4_value
                
                                uds4_df.loc[missing_mask & mask, uds4_var] = pd.to_numeric(uds4_value, errors='coerce')
                            else:
                                uds4_df.loc[mask, uds4_var] = uds4_value

                    else:
                        # Handling structured mathematical mappings (e.g., "PDAGE + BIRTHYR" → "PDYR - BIRTHYR")
                        if any(op in uds3_value for op in ["+", "-", "*", "/"]):
                            uds3_cols = [col.lower() for col in re.findall(r'[A-Za-z0-9_]+', uds4_value)]

                            # Check if the UDS4 variable exists in struct_map1
                            if uds4_var in struct_map1:
                                struct_col = struct_map1[uds4_var]

                                # Ensure struct_col exists in uds3_df and filter out rows where it's non-zero
                                if struct_col in uds3_df.columns:
                                    non_zero_mask = uds3_df[struct_col] != 0  # Mask for non-zero rows

                                    if non_zero_mask.any():  # Proceed only if there's at least one non-zero value
                                        # Ensure all columns exist before computing
                                        if all(col in uds3_df.columns for col in uds3_cols):
                                            # Replace the UDS4 expression with UDS3 column values
                                            uds3_expr = uds4_value.replace("–", "-").strip().lower()
                                
                                            for col in uds3_cols:
                                                uds3_expr = uds3_expr.replace(col, 
                                                                              f"uds3_df.loc[non_zero_mask, '{col}'].fillna(0)")

                                            # Ensure non_zero_mask is passed into eval() explicitly
                                            try:
                                                uds3_computed = eval(uds3_expr, {"uds3_df": uds3_df,
                                                                                 "np": np, "non_zero_mask": non_zero_mask})
                                            except Exception as e:
                                                print(f"Error evaluating UDS3 expression {uds3_expr}: {e}")
                                                uds3_computed = None

                                            # Assign computed values to uds4_df
                                            if uds3_computed is not None:
                                                lev_mask = uds3_df[uds3_var]!=9999
                                                uds4_df.loc[lev_mask & non_zero_mask, uds4_var] = uds3_computed.astype(int)
                                                
                                                # Replace rows where uds3_var is 9999 with 999
                                                replace_mask = uds3_df[uds3_var] == 9999
                                                uds4_df.loc[replace_mask, uds4_var] = 999


                    # This block handles the "paste()" function which is used to combine multiple columns into a single string
                    if "paste(" in uds4_value:
                        # Extracts the column names from inside the paste() function by removing "paste(" and ")" 
                        # and splitting the remaining string by commas
                        comp_raw = uds4_value.replace("paste(", "").replace(")", "").split(',')

                        # Processes each component by stripping whitespace, converting to lowercase
                        # Only keeps components that contain at least one alphanumeric character
                        columns = [comp.strip().lower() for comp in comp_raw if any(c.isalnum() for c in comp.strip())]

                        # Checks if all the extracted column names exist in the uds3_df dataframe
                        if all(comp in uds3_df.columns for comp in columns):
                            # If all columns exist, creates a new column in uds4_df by concatenating values from the 
                            # first three columns in the list, separated by "/" characters
                            # Values are converted to strings to ensure they can be concatenated
                            uds4_df[uds4_var] = (
                                uds3_df[columns[0]].astype(str) + "/" +
                                uds3_df[columns[1]].astype(str) + "/" +
                                uds3_df[columns[2]].astype(str)
                            )

                        else:
                            # If not all columns exist, tries to extract a suffix from the second column name
                            # The regex looks for 1-2 underscores followed by a pattern like 'a2' or 'a5d2'
                            match = re.search(r'_{1,2}([a-d]\d*(d2)?)$', columns[1]) 

                            # If a suffix is found
                            if match:
                                # Extracts the suffix (e.g., 'b5' or 'a5d2')
                                suffix = match.group(1)

                                # Special handling for suffixes containing 'd2'
                                if 'd2' in suffix: 
                                    # Uses only 'd2' instead of the full suffix (e.g., 'a5d2')
                                    sf = 'd2'
                                    # Creates a column name by appending '_form_dt' to the simplified suffix
                                    mapped_column = f"{sf}_form_dt"
                                    # Assigns values from the mapped column in uds3_df to the new column in uds4_df  
                                    uds4_df[uds4_var] = uds3_df[mapped_column]
                                else:
                                    # For other suffixes, constructs a column name with the suffix and '_form_dt'
                                    # Then assigns values from this column in uds3_df to the new column in uds4_df
                                    uds4_df[uds4_var] = uds3_df[f"{suffix}_form_dt"]                  
                        

        # Case 3: No Response LEVELS, copy values directly
        # This block handles the case where there are no response levels defined, and simply copies the values from uds3 to uds4
        elif not response_levels and mapping_type!='Structured_Transformations':
           
            # Check if uds3_var exists in the uds3_df DataFrame
            if uds3_var in uds3_df.columns:
                # If uds4_var exists in the uds4_df DataFrame, copy values only where uds4_var is NA
                if uds4_var in uds4_df.columns:
                    mm = uds4_df[uds4_var].isna()  # Identify rows where uds4_var is missing (NA)
                    uds4_df.loc[mm, uds4_var] = uds3_df[uds3_var]  # Copy corresponding values from uds3_df to uds4_df where uds4_var is NaN
                else:
                    # If uds4_var doesn't exist in uds4_df, directly assign the entire column from uds3_df to uds4_df
                    uds4_df[uds4_var] = uds3_df[uds3_var]

        # Case 4: Conformity check
        # This block handles cases where conformity is checked, i.e., ensuring UDS3 and UDS4 values match based on predefined mappings
        elif conformity:
            # Extract all UDS3 conformity values into a set
            uds3_conformity_values = set(item["UDS3_value"] for mapping in conformity for item in mapping["mappings"])

            # Extract all UDS4 conformity values into a set
            uds4_conformity_values = set(item["UDS4_value"] for mapping in conformity for item in mapping["mappings"])

            # Extract all notes associated with the conformity mappings
            note = set(item["note"] for mapping in conformity for item in mapping["mappings"])
            
            uds3_processed_values = set()

            for value in uds3_conformity_values:
                
                value = str(value)

                if "|" in value:
                    # Split and keep the first part
                    first_part = value.split("|")[0].strip()
                    uds3_processed_values.add(first_part)
                
                elif "Any" in value:

                    uds3_processed_values.add(value.rstrip("."))
                    
                else:
                    uds3_processed_values.add(value)

            # Check if UDS3 and UDS4 conformity values match
            if uds3_processed_values == uds4_conformity_values:
                
                if uds3_var in a3_list:
                    process_repeating_variables(uds3_var, uds4_var, uds3_df, uds4_df)

                # If notes contain "MAX(", it indicates we need to handle special cases (e.g., max across multiple columns)
                elif "MAX(" in str(note):
                    note_str = str(note).strip("{}'")  # Clean up the note string by removing unwanted characters
                    cols = re.findall(r'\b\w+\b', note_str)  # Extract column names from the note string
                    uds3_vars = [col.lower() for col in cols[1:]]  # Convert column names to lowercase (ignoring the first column)

                    # If all extracted columns exist in uds3_df, calculate the maximum value across them
                    if all(col in uds3_df.columns for col in uds3_vars):
                        uds4_df[uds4_var] = uds3_df[uds3_vars].max(axis=1)
                
                # If uds3_var exists in uds3_df, directly copy its values to uds4_df
                elif uds3_var in uds3_df.columns:
                    if uds4_var in uds4_df:
                        mask = uds4_df[uds4_var].isna()
                        uds4_df.loc[mask, uds4_var] = uds3_df[uds3_var]
                    
                    else: 
                       
                        uds4_df[uds4_var] = uds3_df[uds3_var]
            
            else:
                # If conformity values don't match, create a mapping from UDS3 values to UDS4 values based on response_levels
                response_map = {str(item["UDS3_value"]): str(item["UDS4_value"]) 
                                for mapping in response_levels for item in mapping["mappings"]}
                
                if uds3_var in a3_list:
                    process_repeating_variables(uds3_var, uds4_var, uds3_df, uds4_df,response_map)

                # Handle conformity mappings, including both UDS4 conformity and UDS3 response levels
                elif uds3_var in uds3_df.columns:
                    
                    # Apply exact single-value mappings first (e.g., 2 -> 1)
                    for uds3_value, uds4_value in response_map.items():
    
                        # Skip UDS3 values containing "|" or "grep("
                        if "|" not in uds3_value and "grep(" not in uds3_value:
                            # If UDS3 column has float type, convert and map
                            if pd.api.types.is_float_dtype(uds3_df[uds3_var]):
                                float_uds3_value = float(uds3_value)
                                uds4_df.loc[uds3_df[uds3_var] == float_uds3_value, uds4_var] = uds4_value
                            
                                # special case for dysarth, postinst and impnomci columns
                            elif uds3_value == 'None':
                                uds4_df.loc[pd.isnull(uds3_df[uds3_var]), uds4_var] = uds4_value
    
                            else:
                                # Otherwise, map based on string values
                                uds4_df.loc[uds3_df[uds3_var].astype(str) == uds3_value, uds4_var] = uds4_value
           

                        else:
                            # Skip columns with names ending in "sec" or "ter" (those are not mapped)
                            if not (uds3_var.endswith("sec") or uds3_var.endswith("ter")):
                                # Handle cases with logical OR conditions (e.g., "1 | 3 | 4 | 5 | 50 | 99" -> None)
                                values = uds3_value.split(" | ")  # Split values by " | " separator
                                uds4_df.loc[uds3_df[uds3_var].astype(str).isin(values), uds4_var] = uds4_value
    

                    # Handling grep-based text searches (e.g., grep("guatemalan", HISPORX))
                    for uds3_value, uds4_value in response_map.items():
                        if "grep(" in uds3_value:
                            # Extract the search term from the grep function
                            search_term = re.search(r'grep\("(.*?)",', uds3_value).group(1).lower()
                            # Apply the search term to find matching rows in uds3_df
                            uds4_df.loc[uds3_df[uds3_var].astype(str).str.contains(search_term, case=False, na=False), uds4_var] = uds4_value

                    # If the mapping type is not 'Structured_Transformations' or 'High_Complexity', preserve non-mapped values
                    if mapping_type not in ['Structured_Transformations','High_Complexity']:
                        # Ensure all values from uds3_df are preserved in uds4_df where they are not mapped
                        if response_map:
                            if "grep(" not in uds3_value:
                                uds4_df.loc[~uds4_df[uds4_var].isin(response_map.values()), uds4_var] = uds3_df[uds3_var].astype(str)              



# Main Function to process the JSON files and apply crosswalk logic to them
def process_all_jsons(directory):
    
    # Load the JSON files from the specified directory
    mapping_data = load_json_files(directory)
    
    # Iterate through each JSON file in the loaded mapping data
    for json_file, json_data in mapping_data.items():
        print(f"Processing {json_file}...")  # Log the current JSON file being processed

        # Define the list of mapping types to process for each JSON file
        mapping_types = ["Direct_Mappings", "Conditional_Consistency", "Structured_Transformations", "High_Complexity"]
        
        # Loop through each mapping type and process it
        for mapping_type in mapping_types:
            print(f"  Processing {mapping_type} mappings...")  # Log the current mapping type being processed
            process_mappings(json_data, mapping_type)  # Call the function to process mappings for the given type
        
        print(f"Completed processing {json_file}")  # Log that processing of the current JSON file is complete

# Function to replace 'NaN' or '<NA>' values in a DataFrame with 'NA'
def replace_nan_and_na(df):
    return df.applymap(lambda x: "NA" if (pd.isna(x) or x == "<NA>") else x)  # Apply replacement to all elements in the DataFrame

# Cross-checking the data in the uds4_df DataFrame and handling missing values based on a3_stop_dict
def data_crosscheck(uds4_df):
    # Iterate through each column (uds4_var) in the uds4_df DataFrame
    for uds4_var in uds4_df.columns:
        # Check if the current column name (uds4_var) exists in a3_stop_dict
        if uds4_var in a3_stop_dict:
            # Create a boolean mask to identify rows where the value in the column is missing
            logic_mask = uds4_df[uds4_var].isna()
            
            # For rows where the value is missing, replace it with the corresponding value from a3_stop_dict
            # The mapping in a3_stop_dict provides the replacement value for that particular variable
            uds4_df.loc[logic_mask, a3_stop_dict[uds4_var]] = 'NA'


def process_and_save_data(file_path, final_df, output_file):
    # Load UDS4 data elements from the provided file and convert them to lowercase
    with open(file_path, 'r') as file:
        loaded_uds4_data_elements = [line.strip().lower() for line in file.readlines()]
    
    # Filter valid columns from final_df based on the loaded UDS4 data elements
    valid_columns = [col for col in loaded_uds4_data_elements if col in final_df.columns]
    
    # Reorder the DataFrame to include only the valid columns
    final_filtered_df = final_df[valid_columns]
    
    # Save the filtered DataFrame to a CSV file with UTF-8-SIG encoding to avoid character corruption
    final_filtered_df.to_csv(output_file, index=False, na_rep="NA", encoding='utf-8-sig')


# Define the categories and their respective suffixes
categories = {
    'a': [1, 2, 3, 4,5],
    'b': [1, 4, 5, 6, 7, 8, 9],
    'c': [2],
    'd': [1,2]
}

data_dict = {}

for category, numbers in categories.items():
    for num in numbers:
        key_suffix = f"__{category}{num}"
        data_dict[f'ptid{key_suffix}'] = 'adc_sub_id'
        data_dict[f'formver{key_suffix}'] = 'form_ver_num'
        data_dict[f'adcid{key_suffix}'] = 'adc_cntr_id'
        data_dict[f'visitnum{key_suffix}'] = f'{category}{num}_visit_day'
        data_dict[f'initials{key_suffix}'] = f'{category}{num}_ex_ini'

a3_stop_dict = {
    'mometpr': ['mommeval', 'momageo'],
    'dadetpr': ['dadmeval', 'dadageo'],
    **{f'kid{i}etpr': [f'kid{i}meval', f'kid{i}age'] for i in range(1, 16)},
    **{f'sib{i}etpr': [f'sib{i}meval', f'sib{i}age'] for i in range(1, 21)}
}

struct_map1 = {'hrtattage':'cvhatt','strokage':'cbstroke','pdage':'pd','lasttbi':'tbi','pdothrage':'pdothr','tiaage':'cbtia'}

a3_list = ['sib###yob', 'sib###agd','sib###pdx','kid###yob', 'kid###agd','kid###pdx']

########################### Main Process #############################################

# #Define paths for interactive running
# uds3_data_path = io.StringIO('C:\PATH\TO\UDS3\<UDS3_data_file>.csv')
# json_folder_path = is.StringIO('C:\PATH\TO\JSON\FOLDER\')
# data_order_path = io.StringIO('C:\PATH\TO\ORDER\FOLDER\')

# Provide UDS3 data as input - try to provide the label data
nacc = pd.read_csv(uds3_data_path)
print(f"UDS3_data has {nacc.shape[0]} rows and {nacc.shape[1]} columns")

# Defining the UDS4 data frame
uds4_df = pd.DataFrame()

# Convert float-like strings to integers and pad with zeros
nacc['momprdx'] = nacc['momprdx'].apply(lambda x: f"{float(x):03.0f}" if pd.notnull(x) else "NA")
nacc['dadprdx'] = nacc['dadprdx'].apply(lambda x: f"{float(x):03.0f}" if pd.notnull(x) else "NA")

# Copying the nacc_data to uds3_df
uds3_df = nacc.copy()
uds3_df.columns = uds3_df.columns.str.lower()

# Data Type conversion to match the values
float_columns = uds3_df.select_dtypes(include=['float']).columns

for col in float_columns:
    # Convert to numeric, coerce errors to NaN
    uds3_df[col] = pd.to_numeric(uds3_df[col], errors='coerce')

    # Replace infinities with NaN
    uds3_df[col] = uds3_df[col].replace([np.inf, -np.inf], np.nan)

    # Check if all remaining values are safe for integer conversion
    if uds3_df[col].dropna().apply(float.is_integer).all():
        uds3_df[col] = uds3_df[col].astype("Int64")  # Convert to nullable integer
    else:
        print(f"Skipping column '{col}' due to non-integer values.")

# Final process 
directory = json_folder_path

# Process all the json data
process_all_jsons(directory)

# Data Validation - Correcting the UDS4 data
data_crosscheck(uds4_df)

# Saving the appropriate data
final_df = replace_nan_and_na(uds4_df)

# Saving the ordered data
process_and_save_data(
    data_order_path, 
    final_df, 
    "uds4_redcap_data.csv")

print("Your Data Migration from UDS3 to UDS4 is Completed")
