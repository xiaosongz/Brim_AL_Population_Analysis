# scripts/03_process_data.R
library(tidyverse)
library(sf)

# 1. Load Data
acs_raw <- read_rds("data/processed/acs_raw_data.rds")
properties <- read_rds("data/processed/property_master_list.rds")

# 2. Parse Financials from Property List
parse_financials <- function(raw_line) {
  # Extract all matches of $...
  amounts <- str_extract_all(raw_line, "\\$[0-9,]+")[[1]] %>% 
    str_remove_all("[\\$,]") %>% 
    as.numeric()
  
  # Expecting 5 amounts: Acq, Reno, Total, FMV, Equity
  if(length(amounts) >= 5) {
    n <- length(amounts)
    return(tibble(
      acquisition_cost = amounts[n-4],
      renovation_cost = amounts[n-3],
      total_cost = amounts[n-2],
      fair_market_value = amounts[n-1],
      equity = amounts[n]
    ))
  } else {
    return(tibble(
      acquisition_cost = NA, renovation_cost = NA, total_cost = NA, fair_market_value = NA, equity = NA
    ))
  }
}

properties_financials <- properties %>% 
  mutate(financials = map(raw_line, parse_financials)) %>% 
  unnest(financials)

# 3. Inflation Adjustment (CPI-U-RS or similar)
# Using a simplified CPI table for 2013-2023 (Base 2023)
cpi_table <- tibble(
  year = 2013:2023,
  cpi = c(232.957, 236.736, 237.017, 240.007, 245.120, 251.107, 255.657, 258.811, 270.970, 292.655, 304.702)
) %>% 
  mutate(adj_factor = 304.702 / cpi) # Multiplier to get to 2023 dollars

# 4. Process ACS Data
# Join with CPI and adjust Income and Rent
process_acs <- function(df) {
  df %>% 
    left_join(cpi_table, by = "year") %>% 
    mutate(
      med_income_real = med_incomeE * adj_factor,
      med_rent_real = med_rentE * adj_factor
    )
}

tract_data_processed <- acs_raw$tract %>% process_acs()
county_data_5yr_processed <- acs_raw$county_5yr %>% process_acs()
county_data_1yr_processed <- acs_raw$county_1yr %>% process_acs()

# 5. Classify Tracts (Growth/Stable/Weakening)
classify_tract <- function(df) {
  # Filter for start and end points
  # Using 2013 and 2022 (latest 5yr in our fetch)
  start_yr <- 2013
  end_yr <- 2022 # or max(df$year)
  
  df_filtered <- df %>% filter(year %in% c(start_yr, end_yr))
  
  if(nrow(df_filtered) < 2) return(NULL)
  
  start <- df_filtered %>% filter(year == start_yr)
  end <- df_filtered %>% filter(year == end_yr)
  
  # Calculate Changes
  pop_change = (end$total_popE - start$total_popE) / start$total_popE
  income_change_real = (end$med_income_real - start$med_income_real) / start$med_income_real
  rent_change_real = (end$med_rent_real - start$med_rent_real) / start$med_rent_real
  vacancy_change = (end$vacantE / end$total_unitsE) - (start$vacantE / start$total_unitsE)
  
  # Classification Logic
  # Growth: Pop > 0, Real Income > 5% (over decade), Vacancy decreasing or stable
  # Weakening: Pop < -5%, Real Income < 0, Vacancy increasing
  # Stable: Else
  
  classification <- case_when(
    pop_change > 0 & income_change_real > 0.05 ~ "Growth",
    pop_change < -0.05 | income_change_real < -0.05 | vacancy_change > 0.02 ~ "Weakening",
    TRUE ~ "Stable"
  )
  
  tibble(
    GEOID = unique(df$GEOID),
    classification = classification,
    pop_change = pop_change,
    income_change_real = income_change_real,
    rent_change_real = rent_change_real,
    vacancy_change = vacancy_change
  )
}

tract_classifications <- tract_data_processed %>% 
  group_by(GEOID) %>% 
  group_split() %>% 
  map_dfr(classify_tract)

# 6. Merge Everything
final_data <- list(
  properties = properties_financials,
  tract_history = tract_data_processed,
  county_history_5yr = county_data_5yr_processed,
  county_history_1yr = county_data_1yr_processed,
  tract_classifications = tract_classifications
)

write_rds(final_data, "data/processed/final_analytical_data.rds")
message("Data Processing Complete. Saved to data/processed/final_analytical_data.rds")
