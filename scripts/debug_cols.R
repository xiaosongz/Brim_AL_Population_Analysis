# scripts/debug_cols.R
library(tidyverse)
final_data <- read_rds("data/processed/final_analytical_data.rds")
print(colnames(final_data$county_history_1yr))
