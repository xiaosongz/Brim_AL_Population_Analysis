# scripts/debug_cols.R
# Debug utility to inspect column names in processed data structures

# Load required libraries --------------------------------------------------------
library(tidyverse)    # Data manipulation and inspection tools

# Load and inspect final analytical data structure -------------------------------
final_data <- read_rds("data/processed/final_analytical_data.rds")

# Display column names for key data structures
message("County 1-year history columns:")
print(colnames(final_data$county_history_1yr))

message("\nTract history columns:")
print(colnames(final_data$tract_history))

message("\nAvailable data structures:")
print(names(final_data))
