# UDS Crosswalk Parser - R Version
# Libraries needed
library(jsonlite)
library(dplyr)
library(stringr)
library(readr)

# Suppress warnings
options(warn = -1)

# # Command line arguments handling
# args <- commandArgs(trailingOnly = TRUE)
# if (length(args) > 2) {
#   # Inputs -- 1. UDS3 Recap Data path, 2.Json Crosswalk folder path, 3. UDS3_Data_Elements_list
#   uds3_data_path <- args[1]
#   json_folder_path <- args[2]
#   data_order_path <- args[3]
# } else {
#   cat("Please Provide the UDS3_data, Json Crosswalk Folder and Data Order paths\n")
#   quit(save = "no", status = 1)
# }

# Function to load JSON files
load_json_files <- function(directory) {
  json_files <- list.files(directory, pattern = "\\.json$", full.names = TRUE)
  mapping_data <- list()
  
  for (json_file in json_files) {
    file_name <- basename(json_file)
    mapping_data[[file_name]] <- fromJSON(json_file, simplifyDataFrame = FALSE)
  }
  
  return(mapping_data)
}

# Modify the process_repeating_variables function to handle column existence
process_repeating_variables <- function(uds3_var, uds4_var, uds3_df, uds4_df, response_map = NULL) {
  # Check if variable contains 'kid' or 'sib'
  if (!grepl("(kid|sib)", uds3_var)) {
    return(uds4_df)
  }
  
  word <- ifelse(grepl("kid", uds3_var), "kid", "sib")
  rng <- ifelse(word == "kid", 15, 20)
  
  # Clean up base variable names
  base_var <- gsub(word, "", uds3_var)
  base_var <- gsub("#", "", base_var)
  base_var1 <- gsub(word, "", uds4_var)
  base_var1 <- gsub("#", "", base_var1)
  
  for (i in 1:rng) {
    new_uds3_col <- paste0(word, i, base_var)
    new_uds4_col <- paste0(word, i, base_var1)
    
    if (!(new_uds3_col %in% colnames(uds3_df))) {
      next
    }
    
    # Ensure the column exists in uds4_df
    if (!(new_uds4_col %in% colnames(uds4_df))) {
      uds4_df[[new_uds4_col]] <- NA
    }
    
    if (!is.null(response_map)) {
      # Create mapping for values
      col_values <- as.character(uds3_df[[new_uds3_col]])
      
      mapped_values <- sapply(col_values, function(val) {
        # Check if val exists in response_map
        if (val %in% names(response_map)) {
          return(response_map[[val]])
        } else {
          return(val)  # If not found, return the original value
        }
      })
      
      
      # Handle unmatched values
      if (!endsWith(new_uds4_col, "tpr")) {
        response_map_values <- unlist(response_map)
        not_in_map <- !(mapped_values %in% response_map_values)
        mapped_values[not_in_map] <- col_values[not_in_map]
      }
      
      uds4_df[[new_uds4_col]] <- mapped_values
    } else {
      # Directly copy the values if no response map
      uds4_df[[new_uds4_col]] <- uds3_df[[new_uds3_col]]
    }
  }
  
  return(uds4_df)  # Return the updated dataframe
}


# Process mappings function
process_mappings <- function(mapping_data, mapping_type) {
  # Get the list of mappings for the mapping type
  mappings <- mapping_data[[mapping_type]] %||% list()
  
  # Iterate through each mapping
  for (mapping in mappings) {
    # Extract and normalize UDS3 and UDS4 variable names
    uds3_var <- tolower(mapping$UDS3_variable)
    uds4_var <- tolower(mapping$UDS4_variable)
    
    # Resolve UDS3 variable names using data dictionary
    uds3_var <- data_dict[[uds3_var]] %||% uds3_var
    
    # Initialize structured mappings list
    structured_mappings <- list()
    
    # Handle different mapping types
    if (mapping_type == "Direct_Mappings") {
      response_levels <- Filter(function(m) m$mapping_type == "Response LEVELS", mapping$crosswalk_remappings)
      conformity <- Filter(function(m) m$mapping_type == "Conformity", mapping$crosswalk_remappings)
    } else {
      response_levels <- Filter(function(m) m$mapping_type == "Response LEVELS", mapping$crosswalk_mappings %||% list())
      conformity <- Filter(function(m) m$mapping_type == "Conformity", mapping$crosswalk_mappings %||% list())
      structured_mappings <- Filter(function(m) m$mapping_type == "Structured mapping", mapping$crosswalk_mappings %||% list())
    }
    
    # Special Case: Handling cases with " | " separator
    if (grepl("\\|", uds3_var) && length(structured_mappings) == 0) {
      uds3_vars <- strsplit(uds3_var, " \\| ")[[1]]
      
      if (length(uds3_vars) == 2) {
        primary_col <- uds3_vars[1]
        secondary_col <- uds3_vars[2]
        
        if (primary_col %in% colnames(uds3_df) && secondary_col %in% colnames(uds3_df)) {
          # Handle both NA and 'NA' cases
          mask <- is.na(uds3_df[[primary_col]]) | uds3_df[[primary_col]] == "NA"
          uds3_df[mask, primary_col] <- uds3_df[mask, secondary_col]
          uds3_var <- primary_col
        } else if (primary_col %in% colnames(uds3_df)) {
          uds3_var <- primary_col
        } else {
          uds3_var <- secondary_col
        }
      }
    }
    
    # Case 1: Response levels and no conformity
    if (length(response_levels) > 0 && length(conformity) == 0 && uds3_var %in% colnames(uds3_df)) {
      # Create response map
      response_map <- setNames(
        sapply(response_levels, function(mapping) sapply(mapping$mappings, function(item) item$UDS4_value)),
        sapply(response_levels, function(mapping) sapply(mapping$mappings, function(item) item$UDS3_value))
      )
      
      # Apply mappings
      for (uds3_value in names(response_map)) {
        uds4_value <- response_map[[uds3_value]]
        
        if (!grepl("\\|", uds3_value) && !grepl("grep\\(", uds3_value)) {
          if (uds4_var %in% colnames(uds4_df)) {
            # Find rows where 'uds4_var' is NA in 'uds4_df'
            stm <- is.na(uds4_df[[uds4_var]])
            
            # Create the condition for matching values in 'uds3_df' and 'uds3_value'
            update_rows <- stm & (as.character(uds3_df[[uds3_var]]) == uds3_value)
            
            if (!all(is.na(update_rows))) { 
              # Perform the assignment where the condition is TRUE
              uds4_df[!is.na(update_rows), uds4_var] <- uds4_value
            }
            

          }
          else {
            # Replace only where condition is TRUE (excluding NAs)
            uds4_df[!is.na(uds3_df[[uds3_var]]) & as.character(uds3_df[[uds3_var]]) == uds3_value, uds4_var] <- uds4_value
          }
        }
      }
      
    }
    # Case 2: Structured mappings
    else if (length(structured_mappings) > 0) {
      for (struct_map in structured_mappings) {
        for (mapping_entry in struct_map$mappings) {
          uds3_value <- mapping_entry$UDS3_value
          uds4_value <- mapping_entry$UDS4_value
          
          # Handling conditional IF-ELSE structured mappings
          if (grepl("IF\\(", uds3_value)) {
            
            uds3_vars <- strsplit(uds3_var, " \\| ")[[1]]
            
            # Create response map
            response_map <- list()
            for (mapping_item in response_levels) {
              for (item in mapping_item$mappings) {
                response_map[[as.character(item$UDS3_value)]] <- as.character(item$UDS4_value)
              }
            }
            
            for (uds3_val in names(response_map)) {
              uds4_val <- response_map[[uds3_val]]
              
              # Determine logical operator (AND / OR)
              operator <- if (grepl("\\|", uds3_val)) "\\|" else "&"
              
              # Split the values correctly
              values <- unlist(strsplit(uds3_val, paste0(" ", operator, " ")))
              
              if (operator == "\\|") {  # OR condition
                condition <- rep(FALSE, nrow(uds3_df))  # Start with all FALSE
                
                for (i in seq_along(uds3_vars)) {
                  col <- uds3_vars[i]
                  val <- values[i]
                  
                  if (val %in% c("NA", "NULL")) {
                    condition <- condition | is.na(uds3_df[[col]]) | as.character(uds3_df[[col]]) == "NA"
                  } else {
                    condition <- condition | (as.character(uds3_df[[col]]) == val)
                  }
                }
                
              } else {  # AND condition
                condition <- rep(TRUE, nrow(uds3_df))  # Start with all TRUE
                
                for (i in seq_along(uds3_vars)) {
                  col <- uds3_vars[i]
                  val <- values[i]
                  
                  if (val %in% c("NA", "NULL")) {
                    condition <- condition & (is.na(uds3_df[[col]]) | as.character(uds3_df[[col]]) == "NA")
                  } else {
                    condition <- condition & (as.character(uds3_df[[col]]) == val)
                  }
                  
                }
              }
              
              # Apply transformation safely using which(condition)
              uds4_df[which(condition), uds4_var] <- uds4_val
            }
          }
          
          # Identify separator: OR ('|') or AND ('&')
          separator <- NULL
          if (grepl("\\|", uds3_value)) {
            separator <- "\\|"
          } else if (grepl("&", uds3_value)) {
            separator <- "&"
          }
          
          # Handle multiple UDS3 variables with conditions
          if (!is.null(separator)) {
            uds3_vars <- trimws(unlist(strsplit(uds3_var, separator)))
            uds3_values <- trimws(unlist(strsplit(uds3_value, separator)))
            
            # Check if all columns exist
            if (all(uds3_vars %in% colnames(uds3_df))) {
              conditions <- list()
              
              for (i in seq_along(uds3_vars)) {
                # Handle NA properly
                conditions[[i]] <- ifelse(is.na(uds3_df[[uds3_vars[i]]]), FALSE, as.character(uds3_df[[uds3_vars[i]]]) == uds3_values[i])
              }
              
              # Apply OR or AND logic
              mask <- if (separator == "\\|") Reduce(`|`, conditions) else Reduce(`&`, conditions)
              
              # Update where conditions match
              if (uds4_var %in% colnames(uds4_df)) {
                missing_mask <- is.na(uds4_df[[uds4_var]])  # Only update missing values
                rows_effect <- missing_mask & mask  # Corrected filtering
                
                uds4_df[rows_effect, uds4_var] <- as.numeric(uds4_value)
              } else {
                uds4_df[mask, uds4_var] <- uds4_value
              }
            }
          }
          else {
            # Handle structured mathematical mappings
            if (any(grepl("[\\+\\-\\*/]", uds3_value))) {
              uds3_cols <- str_extract_all(uds4_value, "\\b\\w+\\b") %>% unlist() %>% tolower()
              
              # Check if UDS4 variable exists in struct_map1
              if (uds4_var %in% names(struct_map1)) {
                struct_col <- struct_map1[[uds4_var]]
                
                # Ensure struct_col exists and filter non-zero rows
                if (struct_col %in% colnames(uds3_df)) {
                  non_zero_mask <- !is.na(uds3_df[[struct_col]]) & uds3_df[[struct_col]] != 0
                  
                  if (any(non_zero_mask)) {
                    # Ensure all columns exist
                    if (all(uds3_cols %in% colnames(uds3_df))) {
                      # Replace the UDS4 expression with R code
                      uds3_expr <- gsub("–", "-", trimws(tolower(uds4_value)))
                      
                      # Create a data frame subset for non-zero rows
                      subset_df <- uds3_df[non_zero_mask, , drop = FALSE]
                      
                      # Prepare environment for evaluation
                      env <- new.env()
                      for (col in uds3_cols) {
                        env[[col]] <- subset_df[[col]]
                      }
                      
                      # Evaluate expression
                      tryCatch({
                        uds3_computed <- eval(parse(text = uds3_expr), envir = env)
                        
                        # Ensure valid results
                        lev_mask <- !is.na(uds3_df[[uds3_var]]) & uds3_df[[uds3_var]] != 9999
                        uds4_df[lev_mask & non_zero_mask, uds4_var] <- as.integer(uds3_computed)
                        
                        # Replace rows where uds3_var is 9999 with 999
                        replace_mask <- !is.na(uds3_df[[uds3_var]]) & uds3_df[[uds3_var]] == 9999
                        uds4_df[replace_mask, uds4_var] <- 999
                      }, error = function(e) {
                        warning(sprintf("Error evaluating UDS3 expression '%s': %s", uds3_expr, e$message))
                      })
                    }
                  }
                }
              }
            }
          }
          
          # Handle paste() function
          if (grepl("paste\\(", uds4_value)) {
            comp_raw <- gsub("paste\\(|\\)", "", uds4_value) %>% 
              strsplit(",") %>% 
              unlist()
            
            # Process each component
            columns <- trimws(comp_raw) %>% 
              tolower() %>%
              .[grepl("[[:alnum:]]", .)]
            
            if (all(columns %in% colnames(uds3_df))) {
              # Concatenate values with "/"
              uds4_df[[uds4_var]] <- paste(
                as.character(uds3_df[[columns[1]]]),
                as.character(uds3_df[[columns[2]]]),
                as.character(uds3_df[[columns[3]]]),
                sep = "/"
              )
            } else {
              # Try to extract suffix
              match <- str_match(columns[2], "_{1,2}([a-d]\\d*(d2)?)$")
              
              if (!is.na(match[1,2])) {
                # Extract suffix
                suffix <- match[1,2]
                
                if (grepl("d2", suffix)) {
                  sf <- "d2"
                  mapped_column <- paste0(sf, "_form_dt")
                  uds4_df[[uds4_var]] <- uds3_df[[mapped_column]]
                } else {
                  uds4_df[[uds4_var]] <- uds3_df[[paste0(suffix, "_form_dt")]]
                }
              }
            }
          }
        }
      }
    }
    # Case 3: No response levels, copy directly
    else if (length(response_levels) == 0 && mapping_type != "Structured_Transformations") {
      
      if (uds3_var %in% colnames(uds3_df)) {
        if (uds4_var %in% colnames(uds4_df)) {
          mm <- is.na(uds4_df[[uds4_var]])
          uds4_df[mm, uds4_var] <- uds3_df[uds3_var]
          
        } else {
          uds4_df[[uds4_var]] <- uds3_df[[uds3_var]]
        }
      }
    }
    # Case 4: Conformity check
    else if (length(conformity) > 0) {
      # Extract conformity values
      uds3_conformity_values <- character(0)
      uds4_conformity_values <- character(0)
      notes <- character(0)
      
      for (mapping_item in conformity) {
        for (item in mapping_item$mappings) {
          uds3_conformity_values <- c(uds3_conformity_values, as.character(item$UDS3_value))
          uds4_conformity_values <- c(uds4_conformity_values, as.character(item$UDS4_value))
          notes <- c(notes, as.character(item$note))
        }
      }
      
      uds3_processed_values <- character(0)
      
      for (value in uds3_conformity_values) {
        value <- as.character(value)
        
        if (grepl("\\|", value)) {
          first_part <- strsplit(value, "\\|")[[1]][1] %>% trimws()
          uds3_processed_values <- c(uds3_processed_values, first_part)
        } else if (grepl("Any", value)) {
          uds3_processed_values <- c(uds3_processed_values, sub("\\.$", "", value))
        } else {
          uds3_processed_values <- c(uds3_processed_values, value)
        }
      }
      
      # Check if conformity values match
      if (setequal(uds3_processed_values, uds4_conformity_values)) {
        if (uds3_var %in% a3_list) {
          uds4_df <- process_repeating_variables(uds3_var, uds4_var, uds3_df, uds4_df)
        } else if (any(grepl("MAX\\(", notes))) {
          note_str <- paste(notes, collapse = " ")
          cols <- str_extract_all(note_str, "\\b\\w+\\b")[[1]]
          uds3_vars <- tolower(cols[-1])
          
          if (all(uds3_vars %in% colnames(uds3_df))) {
            uds4_df[[uds4_var]] <- apply(uds3_df[, uds3_vars, drop = FALSE], 1, function(row) {
              # Check if all values are NA in the row
              if (all(is.na(row))) {
                return(NA)  # Return NA 
              } else {
                return(max(row, na.rm = TRUE))  # Return max value ignoring NA
              }
            })
          }
          
        } else if (uds3_var %in% colnames(uds3_df)) {
          if (uds4_var %in% colnames(uds4_df)) {
            mask <- is.na(uds4_df[[uds4_var]])
            uds4_df[mask, uds4_var] <- uds3_df[mask, uds3_var]
          } else {
            
            uds4_df[[uds4_var]] <- uds3_df[[uds3_var]]
          }
        }
      } else {
        # Create mapping from UDS3 to UDS4 values
        response_map <- setNames(
          sapply(response_levels, function(mapping) sapply(mapping$mappings, function(item) item$UDS4_value)),
          sapply(response_levels, function(mapping) sapply(mapping$mappings, function(item) item$UDS3_value))
        )
        
        if (uds3_var %in% a3_list) {
          uds4_df <- process_repeating_variables(uds3_var, uds4_var, uds3_df, uds4_df, response_map)
        } else if (uds3_var %in% colnames(uds3_df)) {
          # Apply exact single-value mappings
          for (uds3_value in names(response_map)) {
          
            uds4_value <- response_map[[uds3_value]]
            
            if (!grepl("\\|", uds3_value) && !grepl("grep\\(", uds3_value)) {
              # Handle float type
              if (is.numeric(uds3_df[[uds3_var]])) {
                float_uds3_value <- as.numeric(uds3_value)
                
                # CATCH For tremrest type of columns if no structured mappings
                if(is.na(float_uds3_value)){
                  # do nothing
                  
                }
                
                else{
                  uds4_df[!is.na(uds3_df[[uds3_var]]) & uds3_df[[uds3_var]] == float_uds3_value, uds4_var] <- uds4_value
                }
                
              } else if(uds3_value=='NULL') {
  
                uds4_df[is.na(uds3_df[[uds3_var]]), uds4_var] <- uds4_value
                
              } else {
                uds4_df[!is.na(uds3_df[[uds3_var]])& as.character(uds3_df[[uds3_var]]) == uds3_value, uds4_var] <- uds4_value
              }
            } else {
              # Skip columns with names ending in "sec" or "ter" (those are not mapped)
              
              if (!(endsWith(uds3_var, "sec") || endsWith(uds3_var, "ter"))) {
                # Handle cases with logical OR conditions (e.g., "1 | 3 | 4 | 5 | 50 | 99" -> None)
                values <- strsplit(uds3_value, " \\| ")[[1]]  # Split values by " | " separator
                
                # Create a logical vector for rows where uds3_var is in values
                matches <- which(as.character(uds3_df[[uds3_var]]) %in% values)
                
                # Only proceed if we have matches
                if (length(matches) > 0) {
                  if (is.null(uds4_value)) {
                    # If uds4_value is NULL, set to NA
                    uds4_df[matches, uds4_var] <- NA
                  } else {
                    # Otherwise assign the uds4_value
                    uds4_df[matches, uds4_var] <- uds4_value
                  }
                }
              }
            }
          }
          
          # Handle grep-based text searches
          for (uds3_value in names(response_map)) {
            if (grepl("grep\\(", uds3_value)) {
              # Extract search term
              search_term <- str_match(uds3_value, 'grep\\("(.*?)",')[1,2] %>% tolower()
              # Find matching rows
              matches <- grepl(search_term, tolower(as.character(uds3_df[[uds3_var]])), fixed = TRUE)
              uds4_df[matches, uds4_var] <- response_map[[uds3_value]]
            }
          }
          
          # # If the mapping type is not 'Structured_Transformations' or 'High_Complexity', preserve non-mapped values
          # if (!mapping_type %in% c('Structured_Transformations', 'High_Complexity')) {
          #   
          #   # Ensure response_map exists and relevant columns are present
          #   if (length(response_map) > 0 && uds3_var %in% colnames(uds3_df) && uds4_var %in% colnames(uds4_df)) {
          #     
          #     # Check if uds3_value contains complex expressions
          #     if (!grepl("grep\\(", uds3_value) && (!grepl("(ter|sec)$", uds3_var)))  {
          #       
          #       # Identify rows where uds4_var is NOT in response_map values
          #       not_mapped <- is.na(uds4_df[[uds4_var]]) | !uds4_df[[uds4_var]] %in% unlist(response_map)
          #       
          #       # Ensure we only update if the uds3_value itself is NOT in response_map
          #       valid_updates <- not_mapped & !uds3_df[[uds3_var]] %in% unlist(response_map)
          #       
          #       # Assign values ONLY for valid rows
          #       uds4_df[[uds4_var]][valid_updates] <- as.character(uds3_df[[uds3_var]][valid_updates])
          #       
          #     }
          #   }
          # }
          
          

                    
        }
      }
    }
  }
  return(uds4_df)
}

# Update process_all_jsons to maintain uds4_df consistently
process_all_jsons <- function(directory) {
  # Load JSON files
  mapping_data <- load_json_files(directory)
  
  # Process each JSON file
  for (json_file in names(mapping_data)) {
    cat(sprintf("Processing %s...\n", json_file))
    json_data <- mapping_data[[json_file]]
    
    # Define mapping types
    mapping_types <- c("Direct_Mappings", "Conditional_Consistency", 
                       "Structured_Transformations", "High_Complexity")
    
    # Process each mapping type
    for (mapping_type in mapping_types) {
      cat(sprintf("  Processing %s mappings...\n", mapping_type))
      uds4_df <<- process_mappings(json_data, mapping_type)  # Use global assignment to update uds4_df
    }
    
    cat(sprintf("Completed processing %s\n", json_file))
  }
  
  return(uds4_df)  # Return the final uds4_df
}


# Function to replace NaN with NA
replace_nan_and_na <- function(df) {
  df %>% 
    mutate(across(everything(), ~ ifelse(is.na(.) | . == "<NA>", "NA", .)))
}

# Cross-checking data function
data_crosscheck <- function(uds4_df) {
  for (uds4_var in colnames(uds4_df)) {
    if (uds4_var %in% names(a3_stop_dict)) {
      logic_mask <- is.na(uds4_df[[uds4_var]])
      
      # For each target column in a3_stop_dict
      for (target_col in a3_stop_dict[[uds4_var]]) {
        if (target_col %in% colnames(uds4_df)) {
          uds4_df[logic_mask, target_col] <- NA
        }
      }
    }
  }
  
  return(uds4_df)
}


# Function to process and save data
process_and_save_data <- function(file_path, final_df, output_file) {
  # Load UDS4 data elements
  loaded_uds4_data_elements <- readLines(file_path) %>% 
    trimws() %>% 
    tolower()
  
  # Filter valid columns
  valid_columns <- intersect(loaded_uds4_data_elements, colnames(final_df))
  
  # Reorder dataframe
  final_filtered_df <- final_df[, valid_columns, drop = FALSE]
  
  # Save to CSV
  write.csv(final_filtered_df, output_file, row.names = FALSE, na = "NA", fileEncoding = "UTF-8")
  
}

# Define helper for null/NA handling (similar to %||% operator in purrr)
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}


############################## Defining the dictionaries ############################

# Define categories and their respective suffixes
categories <- list(
  a = c(1, 2, 3, 4, 5),
  b = c(1, 4, 5, 6, 7, 8, 9),
  c = c(2),
  d = c(1, 2)
)

# Initialize data dictionary
data_dict <- list()

for (category in names(categories)) {
  for (num in categories[[category]]) {
    key_suffix <- paste0("__", category, num)
    data_dict[[paste0('ptid', key_suffix)]] <- 'adc_sub_id'
    data_dict[[paste0('formver', key_suffix)]] <- 'form_ver_num'
    data_dict[[paste0('adcid', key_suffix)]] <- 'adc_cntr_id'
    data_dict[[paste0('visitnum', key_suffix)]] <- paste0(category, num, '_visit_day')
    data_dict[[paste0('initials', key_suffix)]] <- paste0(category, num, '_ex_ini')
  }
}

# Define a3_stop_dict
a3_stop_dict <- list(
  mometpr = c('mommeval', 'momageo'),
  dadetpr = c('dadmeval', 'dadageo')
)

# Add kid entries
for (i in 1:15) {
  a3_stop_dict[[paste0('kid', i, 'etpr')]] <- c(
    paste0('kid', i, 'meval'), 
    paste0('kid', i, 'age')
  )
}

# Add sib entries
for (i in 1:20) {
  a3_stop_dict[[paste0('sib', i, 'etpr')]] <- c(
    paste0('sib', i, 'meval'), 
    paste0('sib', i, 'age')
  )
}

# Define struct_map1
struct_map1 <- list(
  hrtattage = 'cvhatt',
  strokage = 'cbstroke',
  pdage = 'pd',
  lasttbi = 'tbi',
  pdothrage = 'pdothr',
  tiaage = 'cbtia'
)

# Define a3_list
a3_list <- c('sib###yob', 'sib###agd', 'sib###pdx', 'kid###yob', 'kid###agd', 'kid###pdx')

########################### Main Process #############################################

# Load UDS3 data
#uds3_data_path<-"C:/Users/jaiga/Downloads/Final_parsing/final_uds3.csv"

uds3_data_path<-"UDS3Mod_for_Jai_Crosswalk_Levels_only.csv"
nacc <- read_csv(uds3_data_path)
cat(sprintf("UDS3_data has %d rows and %d columns\n", nrow(nacc), ncol(nacc)))

# Convert float-like strings to integers and pad with zeros
nacc <- nacc %>%
  mutate(
    momprdx = ifelse(!is.na(momprdx), 
                     sprintf("%03.0f", as.numeric(momprdx)), 
                     "NA"),
    dadprdx = ifelse(!is.na(dadprdx), 
                     sprintf("%03.0f", as.numeric(dadprdx)), 
                     "NA")
  )

# Copy the nacc data to uds3_df and convert column names to lowercase
uds3_df <- nacc
colnames(uds3_df) <- tolower(colnames(uds3_df))

# Data Type conversion
float_columns <- sapply(uds3_df, is.numeric)
float_columns <- names(float_columns[float_columns])

for (col in float_columns) {
  # Convert to numeric, coerce errors to NA
  uds3_df[[col]] <- as.numeric(uds3_df[[col]])
  
  # Replace infinities with NA
  uds3_df[[col]] <- ifelse(is.infinite(uds3_df[[col]]), NA, uds3_df[[col]])
  
  # Check if all remaining values are integers
  if (all(is.na(uds3_df[[col]]) | (uds3_df[[col]] %% 1 == 0), na.rm = TRUE)) {
    uds3_df[[col]] <- as.integer(uds3_df[[col]])
  } else {
    cat(sprintf("Skipping column '%s' due to non-integer values.\n", col))
  }
}


#json_folder_path<-"./Crosswalk"
json_folder_path<-"C:/Users/jaiga/Downloads/Final_parsing/crosswalks"

# Initialize uds4_df properly
uds4_df <- data.frame(matrix(NA, nrow = nrow(uds3_df), ncol = 0))
row.names(uds4_df) <- 1:nrow(uds3_df)

# Process all the JSON data and get the updated uds4_df
uds4_df <- process_all_jsons(json_folder_path)


########################### Data Validation and saving #############################################

# Data Validation - Correcting the UDS4 data
uds4_df <- data_crosscheck(uds4_df)

# Preserving the appropriate data
final_df <- replace_nan_and_na(uds4_df)

data_order_path<-"UDS4Data_ColumnOrder.txt"

process_and_save_data(
  data_order_path, 
  final_df,
  "uds4_redcap_data.csv")
