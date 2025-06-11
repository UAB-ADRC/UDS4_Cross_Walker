# UDS Crosswalk Level and Label Updater

#Check and install libraries
lib_list <- c("lubridate", "openxlsx", "data.table")
installed_libs <- installed.packages()[, "Package"]
new_libs <- lib_list[!(lib_list %in% installed_libs)]
if(length(new_libs) > 0) install.packages(new_libs)

# Libraries needed
library(openxlsx)
library(data.table)


# Suppress warnings
options(warn = -1)

# Command line arguments handling
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 2) {
  # Inputs -- 1. Excel Crosswalk folder path, 2. Path to updated rule set, 3. Path to curated variable list
  cross_path <- args[1]
  new_path <- args[2]
  curated_path <- args[3]
} else if (length(args) == 0 && !identical(Sys.getenv("RSCRIPT_PORTABLE"), "true") && isTRUE(isatty(stdout()))) {
  message("Running interactively, be sure to uncomment the paths in Main Process section")
  # Set empty variables (execution continues without error)
  cross_path <- NULL
  new_path <- NULL
  curated_path <- NULL
} else{
  cat("Please provide the path and name for the (1) folder of Excel Crosswalks, (2) the updated UDS4 dictionary, and (3) Curated list of variables\n")
  quit(save = "no", status = 1)
}



#Function for initial read-in of the dictionary and list
dict_read_in <- function(.new = new_path, .curate = curated_path){
  
  #CSV read in - New dictionary
  new_dict <- tryCatch({
    read.csv(.new, check.names = FALSE)
  }, error = function(e) {
    stop(sprintf("Updated UDS4 CSV dictionary not found at: %s", .new))
  })
  
  #We have modidifiable allowance which coerces any yesno type to have "1, Yes | 0, No" as the choices
  new_dict[[choices_col]][new_dict[["Field Type"]] == 'yesno'] <- "1, Yes | 0, No"

  #Otherwise coerce as normal
  new_dict <- as.data.table(data.frame(Index = c(1:nrow(new_dict)), new_dict, check.names = FALSE))
  new_dict <- new_dict[,colnames(new_dict) %in% redcap_dict[["dictionary"]], with = FALSE]
  
    #Next read in the curated variable list for filtering
  #Read in the curated list, default to whatever is in new_dict if nothing is provided
  curated_var <- tryCatch({
    as.data.table(read.table(.curate, check.names = FALSE, header = FALSE))
  }, error = function(e) {
    warning(sprintf("Curated list of variables not found at: %s; defaulting to all variables in new dictionary\n", .new))
    as.data.table(new_dict[[var_col]])
  })
  colnames(curated_var) <- "var_name"

  #Filter the dictionary according to curation
  new_dict <- new_dict[get(var_col) %in% curated_var$var_name,]
  
  #Create the parsed levels and labels, we do this outside of data.table to get NA's properly handled
  # new_dict[,(redcap_dict$matching$dict[3:4]) := redcap_label_parser(get(choices_col))]
  parsed_labels <- redcap_label_parser(new_dict[[choices_col]])
  na_rows <- which(is.na(new_dict[[choices_col]]) | new_dict[[choices_col]] == "")
  parsed_labels[na_rows,] <- NA
  new_dict[,(redcap_dict$matching$dict[3:4]) := parsed_labels]
  
  #Finally, make all variables name upper for consistency
  new_dict[[var_col]] <- toupper(new_dict[[var_col]])
  
  
  return(new_dict)
}


# Function for loading the crosswalk Excel files
load_cross_files <- function(.directory, .start = 2, .sheet_regex = "UDS4 REDCap") {
  cross_files <- list.files(.directory, pattern = "\\.xlsx$", full.names = TRUE)
  cross_data <- list()
  
  for (.file in cross_files) {
    
    #Working on the current Crosswalk file in the folder
    .cross <- basename(.file)
    
    #Get the UDS4 dictionary sheet for parsing
    sheet_names <- openxlsx::getSheetNames(.file)
    .sheet <- grep(.sheet_regex, sheet_names, value = TRUE)
    cross_data[[.cross]] <- openxlsx::read.xlsx(.file, startRow = .start, sheet = .sheet, check.names = FALSE, sep.names = " ")
    
    #Coerce to data.table and drop extra columns
    cross_data[[.cross]] <- as.data.table(cross_data[[.cross]])
    cross_data[[.cross]] <- cross_data[[.cross]][,colnames(cross_data[[.cross]]) %in% redcap_dict[["crosswalk"]], with = FALSE]
    
    #For consistency, make the variable columns in cross_col all upper (which they should be)
    cross_data[[.cross]][[cross_col]] <- toupper(cross_data[[.cross]][[cross_col]])
    
  }
  
  return(cross_data)
}



#Primary function to compare the fields of the cross walk against the processed UDS4 data dictionary
cross_compare <- function(.cross_data, .new_dict, .drop_header = TRUE){
  
  #Iterate over the cross files in cross data
  cross_process <- lapply(names(.cross_data), function(.cross_name){
    
    #Identify the current form and extract the cross file
    .cross_walk <- .cross_data[[.cross_name]]
    .form <- forms_list[sapply(forms_list, grepl, .cross_name)]
    
    #Pull the matches and mismatches between the crosswalk and the main dictionary
    match_list <- var_matcher(.old = .cross_walk[[cross_col]], .new = .new_dict[[var_col]])
    matched_var <- match_list[["matched"]]
    
    #Process mismatches from the Crosswalk specifically
    mismatch_set <- match_list[["mismatch"]][["prior_only"]]
    #Drop the headers (flagged by __ and the .form) if .drop_header is TRUE
    if(isTRUE(.drop_header)){
      mismatch_set <- mismatch_set[!grepl(paste0("__", .form), mismatch_set)]
      if(length(mismatch_set) == 0) mismatch_set <- NULL
    }
    mismatch_set <- list(cross_only = .cross_walk[get(cross_col) %in% mismatch_set])
    #Name the mismatch list by writer_key
    names(mismatch_set) <- writer_key[["mismatch"]][match(names(mismatch_set), names(writer_key[["mismatch"]]))]
    mismatch_set <- mismatch_set[!sapply(mismatch_set, is.null)]
    
    
    #Iterate over the matched variables
    variable_checks <- lapply(matched_var, function(.var){
      
      #Placeholder text if there's a specific variable to ignore
      if(.var %in% to_ignore) return(list(entry = "Ignored", field = .cross_walk[get(cross_col) == .var,]))
      
      #Pull current entries
      .cross <- .cross_walk[get(cross_col) == .var,]
      .new <- .new_dict[get(var_col) == .var,]
      
      #We limit just to the comparison columns
      .cross <- .cross[, colnames(.cross) %in% redcap_dict$matching$cross, with = FALSE]
      .new <- .new[, colnames(.new) %in% redcap_dict$matching$dict, with = FALSE]
      
      #Reorder according to the dictionary (just in case)
      .cross <- .cross[,order(match(redcap_dict$matching$cross, colnames(.cross))), with = FALSE]
      .new <- .new[,order(match(redcap_dict$matching$dict, colnames(.new))), with = FALSE]
      
      #Pass the names of the crosswalk to the new entry temporarily
      colnames(.new) <- redcap_dict$matching$cross
      
      #Just return if they're identical
      if(identical(.cross, .new)) return(list(entry = "Same", field = .cross))
      
      #Initialize a small dataframe to compare
      .diff <- rbind(.cross, .new)
      
      #sapply on field_compare to check column by column
      diff_cols <- sapply(.diff[,!(colnames(.diff) %in% ignored_fields),with=FALSE], field_compare)
      
      #With comparisons done, give the original names back to .new
      colnames(.new) <- redcap_dict$matching$dict
      
      #If diff_cols is all false, it's still the same
      if(sum(diff_cols)==0)  return(list(entry = "Same", field = .cross))
      
      #Finally, if there's a discrepancy flag them and return new
      .diff <- .diff[, names(diff_cols)[diff_cols], with=FALSE]
      .diff <- data.frame(Variable = .var, Field = colnames(.diff), t(.diff))
      rownames(.diff) <- NULL
      colnames(.diff)[3:4] <- c("Crosswalk", "NewDict")
      return(list(entry = "DIFFERENT", cross_field = .cross, new_field = .new, differences = .diff))
    })
    names(variable_checks) <- matched_var
  
    list(compare = variable_checks, mismatch = mismatch_set)
  })
  
  #Final output
  names(cross_process) <- names(.cross_data)
  return(cross_process)
  
}



#Function to write the comparison results to file
cross_writer <- function(.cross_proc){
  
  #Iterate over the cross files in cross data
  lapply(names(.cross_proc), function(.cross_name){
    
    #Identify the current form and extract the cross file
    .compare <- .cross_proc[[.cross_name]]
    .form <- forms_list[sapply(forms_list, grepl, .cross_name)]
    
    #File initialization
    .file <- paste0( paste0("UDS4_", .form, "_crosswalk_update_", gsub("\\-", "", lubridate::today()), ".xlsx"))
    
    #Limit to only DIFFERENT entries
    .comp <- .compare[["compare"]]
    .comp <- lapply(.comp, function(.slot){
      if(.slot[["entry"]] != "DIFFERENT") { return(NULL)
      } else .slot
    })
    .comp <- .comp[!sapply(.comp, is.null)]
    
    #Step through to return three dataframes
    .comp_proc <- lapply(names(writer_key[["compare"]]), function(.name){
      do.call(rbind, lapply(.comp, `[[`, .name))
    })
    names(.comp_proc) <- writer_key[["compare"]]
    
    #Write the comparisons to file
    if(!is.null(.comp_proc) && length(.comp_proc)>0){
      openxlsx::write.xlsx(c(.compare[["mismatch"]], .comp_proc), file=.file)}
    
    return(NULL)
  })
}


############################## Helper Functions ############################


#Function to compare fields column-wise against a pair of entries
#Can be modified as needed
redcap_label_parser <- function(.col){
  
  #First normalize the splits so it's consistently a single vertical bar
  .col <- stringi::stri_replace_all(.col, regex = "\\s*\\|\\s*", replacement = "\\|")
  
  #Split on the vertical bars as the standard | delimiter
  .col_split <- stringi::stri_split(.col, regex = "\\|")
  
  #Then split on the first comma
  .col_comma_split <- lapply(.col_split, stringi::stri_split, regex = ", ", n = 2)
  
  #Now recompile the splits into a label and level vector
  .col_recompile_list <- lapply(.col_comma_split, function(.split){
    
    #Step through and extract the first values as the levels and second set of values as labels
    .split_compile_levels <- lapply(.split, function(xx){xx[1]})
    .split_compile_levels <- do.call(paste, list(.split_compile_levels, collapse = " | "))
    .split_compile_labels <- lapply(.split, function(xx){xx[2]})
    .split_compile_labels <- do.call(paste, list(.split_compile_labels, collapse = " | "))
    
    #Return them as a vector
    c(.split_compile_levels, .split_compile_labels)
    
  })
  
  #Finally, bind the lists row-wise
  .out <- do.call(rbind, .col_recompile_list)
  .out <- as.data.table(.out)
  colnames(.out) <- redcap_dict[["matching"]][["dict"]][3:4]
  return(.out)
}



#Function to check for different variables after matching to curated_var
var_matcher <- function(.old, .new){
  
  #Matched
  .match <- intersect(.old, .new)
  
  #Unmatched
  .old_mis <- setdiff(.old, .new)
  .new_mis <- setdiff(.new, .old)
  
  #Output
  .out <- list(matched = .match, mismatch = list(prior_only = .old_mis, new_only = .new_mis))
  .out[["mismatch"]] <- .out[["mismatch"]][sapply(.out[["mismatch"]], function(xx){length(xx)>0})]
  
  #Return
  return(.out)
}



#Function to compare fields column-wise against a pair of entries
#Can be modified as needed
field_compare <- function(.field, .reg = ignored_regex){
  
  #Condition 1 - field entries are the same
  if(identical(.field[1], .field[2])) return(FALSE)
  
  #Condition 2 - either field is NA or ""
  if(all(is.na(.field) | .field=="")) return(FALSE)
  
  #Condition 3 - compare against a regular expression we want to filter on
  if(!is.null(.reg) && any(grepl(.reg, .field))) return(FALSE)
  
  #Otherwise consider a mismatch
  return(TRUE)
}



############################## Definitions ############################

#String and dictionaries used for read-ins
var_col <- "Variable / Field Name"
cross_col <- "UDS4 data element name"
choices_col <- "Choices, Calculations, OR Slider Labels"

redcap_dict <- list(crosswalk = c("UDS4 data element name", "UDS4 form", "UDS4 REDCap field label", "Response LEVELS", "Response LABELS"),
                    dictionary = c("Variable / Field Name", "Field Label", "Choices, Calculations, OR Slider Labels"),
                    matching = list(cross = c("UDS4 data element name", "UDS4 REDCap field label", "Response LEVELS", "Response LABELS"),
                                    dict = c("Variable / Field Name", "Field Label", "Response LEVELS", "Response LABELS")))

#The UDS forms we iterate over
forms_list <- c("A1", "A2", "A3", "A4", "A5_D2", "B1", "B4", "B5", "B6", "B7", "B8", "B9", "C2", "D1a_D1b")

#Key for writing
writer_key <- list(mismatch = c(cross_only = "Unmatched - Crosswalk", new_only = "Unmatched - New"),
                   compare = c(cross_field = "Crosswalk Entries", new_field = "New Entries", differences = "Field Differences"))


#Both of these are set to NULL, they don't really have a place in the crosswalk comparison as it stands

#Included variable set to ignore, defaults to NULL, can be modified if so desired
to_ignore <- NULL

#A regular expression that can be modified to be ignored when checking columns
ignored_regex <- NULL

#Fields in eithe rdictionary or crosswalk we'll not compare
ignored_fields <- NULL

########################### Main Process ###############################

#Loading files and folders manually if not running from command line
.cross_path <- .new_path <- .curated_path <- NULL

#.cross_path = normalizePath(file.choose())
#.new_path = normalizePath(file.choose())
#.curated_path = normalizePath(file.choose())

if(is.null(cross_path))  cross_path <- .cross_path
if(is.null(new_path)) new_path <- .new_path
if(is.null(curated_path)) curated_path <- .curated_path
if(is.null(cross_path) || is.null(new_path) || is.null(curated_path)) {
  cat("File paths missing, check command line arguments or uncomment paths at beginning of main process")
  quit(save = "no", status = 1)
}

#Wrapper functions to 1) read-in and process dictionary, 2) read-in series of crosswalks, 3) do the crosswalk update, 4) write to file
new_dict_data <- dict_read_in(.new = new_path, .curate = curated_path)
cross_data <- load_cross_files(.directory = cross_path)
cross_results <- cross_compare(cross_data, new_dict_data, .drop_header = FALSE)
cross_writer(cross_results)








