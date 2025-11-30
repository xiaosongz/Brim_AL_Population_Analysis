# scripts/check_cache_rows.R
library(tidyverse)

file <- "data/raw/acs_cache/acs_zcta_full_acs5_2013.rds"
if (file.exists(file)) {
    data <- read_rds(file)
    message(paste("Rows in 2022 cache:", nrow(data)))
    message(paste("Unique ZCTAs:", length(unique(data$GEOID))))
} else {
    message("File not found.")
}
