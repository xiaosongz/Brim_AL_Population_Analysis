#!/usr/bin/env Rscript
# 04_prepare_dashboard_data.R
# Extracts and cleans data from Sample Dashboard Excel for dashboard visualization

library(readxl)
library(tidyverse)

cat("Loading dashboard data from Excel...\n")

# Read raw Excel data
excel_path <- "data/raw/Sample Dashboard_Clean V1.0.xlsx"
dashboard_raw <- read_excel(excel_path, sheet = "Sample Dashboard", col_names = FALSE)

# --- 1. Extract KPI Summary Data ---
kpi_data <- tibble(

  fund_i_icc = as.numeric(dashboard_raw[[2]][3]),
  fund_ii_icc = as.numeric(dashboard_raw[[2]][4]),
  total_icc = as.numeric(dashboard_raw[[2]][5]),
  unit_count = as.numeric(dashboard_raw[[2]][8]),
  potential_monthly_rent = as.numeric(dashboard_raw[[2]][9]),
  potential_annual_rent = as.numeric(dashboard_raw[[2]][10]),
  potential_noi_2026 = as.numeric(dashboard_raw[[2]][11]),
  potential_cap_rate = as.numeric(dashboard_raw[[2]][12])
)

cat("KPI Data extracted:\n")
print(kpi_data)

# --- 2. Extract T-12 Monthly Time Series ---
months <- c("May", "June", "July", "Aug", "Sept", "Oct")
t12_data <- tibble(
  month = factor(months, levels = months),
  month_num = 5:10,
  egi = as.numeric(c(
    dashboard_raw[[2]][16], dashboard_raw[[3]][16], dashboard_raw[[4]][16],
    dashboard_raw[[5]][16], dashboard_raw[[6]][16], dashboard_raw[[7]][16]
  )),
  fixed_expense = as.numeric(c(
    dashboard_raw[[2]][17], dashboard_raw[[3]][17], dashboard_raw[[4]][17],
    dashboard_raw[[5]][17], dashboard_raw[[6]][17], dashboard_raw[[7]][17]
  )),
  variable_expense = as.numeric(c(
    dashboard_raw[[2]][18], dashboard_raw[[3]][18], dashboard_raw[[4]][18],
    dashboard_raw[[5]][18], dashboard_raw[[6]][18], dashboard_raw[[7]][18]
  )),
  noi = as.numeric(c(
    dashboard_raw[[2]][19], dashboard_raw[[3]][19], dashboard_raw[[4]][19],
    dashboard_raw[[5]][19], dashboard_raw[[6]][19], dashboard_raw[[7]][19]
  )),
  cap_rate = as.numeric(c(
    dashboard_raw[[2]][20], dashboard_raw[[3]][20], dashboard_raw[[4]][20],
    dashboard_raw[[5]][20], dashboard_raw[[6]][20], dashboard_raw[[7]][20]
  ))
)

cat("\nT-12 Monthly Data extracted:\n")
print(t12_data)

# --- 3. Extract Valuation Matrix ---
# Columns 9-28 (NOI values in header row 4), Rows 4-74 (cap rates 3%-10%)
noi_values <- as.numeric(unlist(dashboard_raw[4, 10:28]))
cap_rates <- as.numeric(unlist(dashboard_raw[5:74, 9]))

# Extract valuation matrix and convert to numeric
valuation_df <- dashboard_raw[5:74, 10:28]
valuation_matrix <- matrix(
  as.numeric(unlist(valuation_df)),
  nrow = nrow(valuation_df),
  ncol = ncol(valuation_df),
  byrow = FALSE
)
colnames(valuation_matrix) <- paste0("noi_", round(noi_values / 1000), "k")
rownames(valuation_matrix) <- paste0("cap_", round(cap_rates * 100, 1), "pct")

# Convert to long format for plotting
valuation_long <- expand_grid(
  cap_rate_idx = seq_along(cap_rates),
  noi_idx = seq_along(noi_values)
) |>
  mutate(
    cap_rate = cap_rates[cap_rate_idx],
    noi = noi_values[noi_idx],
    value = map2_dbl(cap_rate_idx, noi_idx, ~ valuation_matrix[.x, .y]),
    cap_rate_pct = cap_rate * 100
  ) |>
  select(-cap_rate_idx, -noi_idx)

cat("\nValuation Matrix dimensions:", nrow(valuation_matrix), "x", ncol(valuation_matrix), "\n")

# --- 4. Extract Loan Affordability Matrix ---
max_ds_values <- as.numeric(unlist(dashboard_raw[4, 31:49]))
io_rates <- as.numeric(unlist(dashboard_raw[5:74, 30]))

# Extract loan matrix and convert to numeric
loan_df <- dashboard_raw[5:74, 31:49]
loan_matrix <- matrix(
  as.numeric(unlist(loan_df)),
  nrow = nrow(loan_df),
  ncol = ncol(loan_df),
  byrow = FALSE
)

loan_long <- expand_grid(
  io_rate_idx = seq_along(io_rates),
  ds_idx = seq_along(max_ds_values)
) |>
  mutate(
    io_rate = io_rates[io_rate_idx],
    max_ds = max_ds_values[ds_idx],
    max_loan = map2_dbl(io_rate_idx, ds_idx, ~ loan_matrix[.x, .y]),
    io_rate_pct = io_rate * 100
  ) |>
  select(-io_rate_idx, -ds_idx)

cat("Loan Affordability Matrix dimensions:", nrow(loan_matrix), "x", ncol(loan_matrix), "\n")

# --- 5. Save processed data ---
dashboard_data <- list(
  kpi = kpi_data,
  t12 = t12_data,
  valuation_long = valuation_long,
  loan_long = loan_long,
  valuation_matrix = valuation_matrix,
  loan_matrix = loan_matrix,
  noi_values = noi_values,
  cap_rates = cap_rates,
  max_ds_values = max_ds_values,
  io_rates = io_rates
)

saveRDS(dashboard_data, "data/processed/dashboard_data.rds")
cat("\nDashboard data saved to: data/processed/dashboard_data.rds\n")
