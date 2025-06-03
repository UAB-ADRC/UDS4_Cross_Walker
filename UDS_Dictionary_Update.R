#UDS4 Dictionary Update Reporter

#Check and install libraries
lib_list <- c("data.table", "lubridate", "openxlsx")
installed_libs <- installed.packages()[, "Package"]
new_libs <- lib_list[!(lib_list %in% installed_libs)]
if(length(new_libs) > 0) install.packages(new_libs)

#Libraries needed
library(data.table)

#Suppress warnings
options(warn = -1)

#Command line arguments handling
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 2) {
  #Inputs -- 1. Old UDS4 dictionary path and name, 2. New UDS4 dictionary path and name, 3. Curated list of variables to check
  prior_path <- args[1]
  new_path <- args[2]
  curated_path <- args[3]
} else if (length(args) == 0 && !identical(Sys.getenv("RSCRIPT_PORTABLE"), "true") && isTRUE(isatty(stdout()))) {
  message("Running interactively, be sure to uncomment the paths in Main Process section")
  #Set empty variables (execution continues without error)
  prior_path <- NULL
  new_path <- NULL
  curated_path <- NULL
} else{
  cat("Please provide the path and name for the (1) prior UDS4 data dictionary, (2) updated UDS4 dictionary for comparison, and (3) Curated list of variables\n")
  quit(save = "no", status = 1)
}


#Function for initial processing and check
dict_read_in <- function(.prior = prior_path, .new = new_path){
  
  #CSV read in - Prior dictionary
  prior_dict <- tryCatch({
    read.csv(.prior, check.names = FALSE)
  }, error = function(e) {
    stop(sprintf("Prior UDS4 CSV dictionary not found at: %s", .prior))
  })
  
  #CSV read in - New dictionary
  new_dict <- tryCatch({
    read.csv(.new, check.names = FALSE)
  }, error = function(e) {
    stop(sprintf("Updated UDS4 CSV dictionary not found at: %s", .new))
  })
  
  
  #Verify column names are identical in the dictionaries
  ident_check <- identical(colnames(prior_dict), colnames(new_dict))
  
  #If column names do not align, do a quick NA investigation on the old dictionary
  if(isFALSE(ident_check)){
    #If non-NA material is found, stop
    ident_all_NA <- lapply(prior_dict[,colnames(prior_dict) %in% setdiff(colnames(prior_dict), colnames(new_dict)), drop=FALSE], function(xx){all(is.na(xx))})
    if(!all(unlist(ident_all_NA))) stop(paste0("Extra non-NA columns found in ", gsub(".*?/", "", .prior)))
    #Otherwise, just return the columns in new_dict
    prior_dict <- prior_dict[, colnames(prior_dict) %in% colnames(new_dict)]
  }
  
  #End by coercing to a data.table object and adding an Index variable for sorting
  prior_dict <- as.data.table(data.frame(Index = c(1:nrow(prior_dict)), prior_dict, check.names = FALSE))
  new_dict <- as.data.table(data.frame(Index = c(1:nrow(new_dict)), new_dict, check.names = FALSE))
  
  return(list(prior_dict = prior_dict, new_dict = new_dict))
}


#Primary function to compare variable content
variable_comparison <- function(.dict_list, .curate){
  
  #Extract the dictionaries for comparison
  prior_dict <- .dict_list[["prior_dict"]]
  new_dict <- .dict_list[["new_dict"]]
  
  #Read in the curated list, default to whatever is in new_dict if nothing is provided
  curated_var <- tryCatch({
    as.data.table(read.table(.curate, check.names = FALSE, header = FALSE))
  }, error = function(e) {
    warning(sprintf("Curated list of variables not found at: %s; defaulting to all variables in new dictionary\n", .new))
    as.data.table(new_dict[[var_col]])
  })
  colnames(curated_var) <- "var_name"
  
  #Limit both dictionaries to the variables in curated_var
  prior_dict <- prior_dict[get(var_col) %in% curated_var[["var_name"]],]
  new_dict <- new_dict[get(var_col) %in% curated_var[["var_name"]],]
  
  #Pull the matches and mismatches
  match_list <- var_matcher(.old = prior_dict[[var_col]], .new = new_dict[[var_col]])
  matched_var <- match_list[["matched"]]
  
  #Process mismatches
  mismatch_set <- lapply(names(writer_key[["mismatch"]]), function(.mismatch){
      if(.mismatch == "prior_only") prior_dict[get(var_col) %in% match_list[["mismatch"]][[.mismatch]]]
      if(.mismatch == "new_only") new_dict[get(var_col) %in% match_list[["mismatch"]][[.mismatch]]]
    })
  names(mismatch_set) <- writer_key[["mismatch"]][match(names(mismatch_set), names(writer_key[["mismatch"]]))]
  mismatch_set <- mismatch_set[!sapply(mismatch_set, is.null)]
  
  
  #Iterate over the matched variables
  variable_checks <- lapply(matched_var, function(.var){
    
    #Placeholder text if there's a specific variable to ignore
    if(.var %in% to_ignore) return(list(entry = "Ignored", field = prior_dict[get(var_col) == .var,]))
    
    #Pull current entries
    .prior <- prior_dict[get(var_col) == .var,]
    .new <- new_dict[get(var_col) == .var,]
    
    #Just return if they're identical
    if(identical(.prior, .new)) return(list(entry = "Same", field = .prior))
    
    #Initialize a small dataframe to compare
    .diff <- rbind(.prior, .new)
    
    #sapply on field_compare to check column by column
    diff_cols <- sapply(.diff[,!(colnames(.diff) %in% ignored_fields),with=FALSE], field_compare)
    
    #If diff_cols is all false, it's still the same
    if(sum(diff_cols)==0)  return(list(entry = "Same", field = .prior))
    
    #Finally, if there's a discrepancy flag them and return new
    .diff <- .diff[, names(diff_cols)[diff_cols], with=FALSE]
    .diff <- data.frame(Variable = .var, Field = colnames(.diff), t(.diff))
    rownames(.diff) <- NULL
    colnames(.diff)[3:4] <- c("PriorDict", "NewDict")
    return(list(entry = "DIFFERENT", prior_field = .prior, new_field = .new, differences = .diff))
  })
  names(variable_checks) <- matched_var
  
  #Final output
  list(compare = variable_checks, mismatch = mismatch_set)
}



#Function to write the comparison results to file
comparison_writer <- function(.compare){
  
  #File initialization
  .file <- paste0( paste0("UDS4_dictionary_comparison_", gsub("\\-", "", lubridate::today()), ".xlsx"))
  
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
}



############################## Helper Functions ############################


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

#Common strings used for processing
var_col <- "Variable / Field Name"
ignored_fields <- c("Index")

#Included variable set to ignore, defaults to NULL, can be modified if so desired
to_ignore <- NULL

#A regular expression that can be modified to be ignored when checking columns
#Default is to ignore any instance of '[current-instance]=1' as an example
#This frequently comes up in Field Annotation which can also just be ignored
ignored_regex <- "\\[current\\-instance\\]=\\'1\\'"


#Key for writing
writer_key <- list(mismatch = c(prior_only = "Unmatched - Prior", new_only = "Unmatched - New"),
                   compare = c(prior_field = "Prior Entries", new_field = "New Entries", differences = "Field Differences"))


########################### Main Process ###############################

#Loading files and folders manually if not running from command line
.prior_path <- .new_path <- .curated_path <- NULL

#.prior_path = normalizePath(file.choose())
#.new_path = normalizePath(file.choose())
#.curated_path = normalizePath(file.choose())

if(is.null(prior_path))  prior_path <- .prior_path
if(is.null(new_path)) new_path <- .new_path
if(is.null(curated_path)) curated_path <- .curated_path
if(is.null(prior_path) || is.null(new_path) || is.null(curated_path)) {
  cat("File paths missing, check command line arguments or uncomment paths at beginning of main process")
  quit(save = "no", status = 1)
}

#Wrapper functions to 1) read-in, 2) do the dictionary comparison, 3) write to file
uds_dict_set <- dict_read_in(.prior = prior_path, .new = new_path)
uds_dict_compare <- variable_comparison(.dict_list = uds_dict_set, .curate = curated_path)
comparison_writer(uds_dict_compare)

