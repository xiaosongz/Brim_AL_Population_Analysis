# scripts/check_cache_rows.R
# Utility script to inspect cache file contents and verify data completeness

# Load required libraries --------------------------------------------------------
library(tidyverse)    # Data manipulation utilities

# Check specific cache file for data completeness --------------------------------
cache_file <- "data/raw/acs_cache/acs_zcta_full_acs5_2013.rds"
if (file.exists(cache_file)) {
  data <- read_rds(cache_file)
  message("Cache file analysis:")
  message("- Total rows: ", nrow(data))
  message("- Unique ZCTAs: ", length(unique(data$GEOID)))
  message("- Years covered: ", paste(unique(data$year), collapse = ", "))
  message("- Variables: ", ncol(data))
} else {
  message("Cache file not found: ", cache_file)
}
