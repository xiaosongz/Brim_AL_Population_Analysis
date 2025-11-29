# scripts/03_process_data.R
library(tidyverse)
library(sf)

if (file.exists(".env")) readRenviron(".env")

# 1. Load Data
acs_raw <- read_rds("data/processed/acs_raw_data.rds")
properties <- read_rds("data/processed/property_master_list.rds")
# Derive county ZCTAs (Jefferson County, AL)
county_geom <- tigris::counties(state = "AL", cb = TRUE, year = 2022, class = "sf") %>%
  dplyr::filter(COUNTYFP == "073") %>%
  st_transform(4326)
zcta_geom_full <- tigris::zctas(cb = TRUE, year = 2020, class = "sf") %>%
  st_transform(4326)
inter_mat <- st_intersects(zcta_geom_full, county_geom, sparse = FALSE)
county_zctas <- zcta_geom_full$ZCTA5CE20[apply(inter_mat, 1, any)] %>% unique()

# 2. Parse Financials from Property List
parse_financials <- function(raw_line) {
  amounts <- str_extract_all(raw_line, "\\$[0-9,]+")[[1]] |>
    str_remove_all("[\\$,]") |>
    as.numeric()

  if (length(amounts) >= 5) {
    n <- length(amounts)
    tibble(
      acquisition_cost = amounts[n - 4],
      renovation_cost = amounts[n - 3],
      total_cost = amounts[n - 2],
      fair_market_value = amounts[n - 1],
      equity = amounts[n]
    )
  } else {
    tibble(
      acquisition_cost = NA_real_,
      renovation_cost = NA_real_,
      total_cost = NA_real_,
      fair_market_value = NA_real_,
      equity = NA_real_
    )
  }
}

properties_financials <- properties |>
  mutate(financials = map(raw_line, parse_financials)) |>
  unnest(financials)
property_crosswalk <- properties_financials |>
  select(
    property_id,
    address_raw,
    full_address,
    tract_geoid,
    zcta5,
    county_fips,
    state_fips
  )
property_tracts <- property_crosswalk$tract_geoid |> na.omit() |> unique()
property_zctas <- property_crosswalk$zcta5 |> na.omit() |> unique()

# 2b. Property counts by geography for summary tables
tract_counts <- property_crosswalk |>
  count(tract_geoid, name = "property_count") |>
  arrange(desc(property_count))

zcta_counts <- property_crosswalk |>
  mutate(zcta5 = coalesce(zcta5, properties$zip[match(property_id, properties$property_id)])) |>
  count(zcta5, name = "property_count") |>
  arrange(desc(property_count))

county_counts <- property_crosswalk |>
  mutate(county_geoid = paste0(state_fips, county_fips)) |>
  count(county_geoid, name = "property_count") |>
  arrange(desc(property_count))

# 3. Inflation Adjustment (CPI-U, annual averages, 2023 dollars)
cpi_table <- tibble(
  year = 2013:2023,
  cpi = c(232.957, 236.736, 237.017, 240.007, 245.120, 251.107, 255.657, 258.811, 270.970, 292.655, 304.702)
) |>
  mutate(adj_factor = max(cpi) / cpi)

# 4. Helper functions for ACS margins of error and significance
se_from_moe <- function(moe) moe / 1.645
moe_from_se <- function(se) se * 1.645
sum_moe <- function(moes) moe_from_se(sqrt(sum(se_from_moe(moes)^2, na.rm = TRUE)))
ratio_moe <- function(num, num_moe, denom, denom_moe) {
  ifelse(
    is.na(num) | is.na(denom) | denom == 0,
    NA_real_,
    moe_from_se(
      sqrt(
        (se_from_moe(num_moe) / denom)^2 +
          ((num * se_from_moe(denom_moe)) / (denom^2))^2
      )
    )
  )
}
diff_moe <- function(moe1, moe2) moe_from_se(sqrt(se_from_moe(moe1)^2 + se_from_moe(moe2)^2))

# Age bucket definitions to approximate spec (<18, 18–25, 26–55, 56–65, 65+)
age_under18_vars <- c(
  "age_m_under5", "age_m_5_9", "age_m_10_14", "age_m_15_17",
  "age_f_under5", "age_f_5_9", "age_f_10_14", "age_f_15_17"
)
age_18_24_vars <- c("age_m_18_19", "age_m_20", "age_m_21", "age_m_22_24", "age_f_18_19", "age_f_20", "age_f_21", "age_f_22_24")
age_30_54_vars <- c(
  "age_m_30_34", "age_m_35_39", "age_m_40_44", "age_m_45_49", "age_m_50_54",
  "age_f_30_34", "age_f_35_39", "age_f_40_44", "age_f_45_49", "age_f_50_54"
)
age_56_64_core <- c("age_m_60_61", "age_m_62_64", "age_f_60_61", "age_f_62_64")
age_67plus_vars <- c(
  "age_m_67_69", "age_m_70_74", "age_m_75_79", "age_m_80_84", "age_m_85_plus",
  "age_f_67_69", "age_f_70_74", "age_f_75_79", "age_f_80_84", "age_f_85_plus"
)

# 5. Process ACS Data with MOE-aware calculations
process_acs <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(tibble())

  df |>
    left_join(cpi_table, by = "year") |>
    rowwise() |>
    mutate(
      # Age buckets (allocation within 5-year groups to respect custom bins)
      age_under18E = sum(c_across(all_of(paste0(age_under18_vars, "E"))), na.rm = TRUE),
      age_under18M = sum_moe(c_across(all_of(paste0(age_under18_vars, "M")))),

      age_18_25E = sum(c_across(all_of(paste0(age_18_24_vars, "E"))), na.rm = TRUE) +
        0.2 * (age_m_25_29E + age_f_25_29E), # approximate 1 year of 25–29 band
      age_18_25M = sum_moe(c(c_across(all_of(paste0(age_18_24_vars, "M"))), 0.2 * age_m_25_29M, 0.2 * age_f_25_29M)),

      age_26_55E = 0.8 * (age_m_25_29E + age_f_25_29E) +
        sum(c_across(all_of(paste0(age_30_54_vars, "E"))), na.rm = TRUE) +
        0.2 * (age_m_55_59E + age_f_55_59E),
      age_26_55M = sum_moe(c(
        0.8 * age_m_25_29M, 0.8 * age_f_25_29M,
        c_across(all_of(paste0(age_30_54_vars, "M"))),
        0.2 * age_m_55_59M, 0.2 * age_f_55_59M
      )),

      age_56_65E = 0.8 * (age_m_55_59E + age_f_55_59E) +
        sum(c_across(all_of(paste0(age_56_64_core, "E"))), na.rm = TRUE) +
        0.5 * (age_m_65_66E + age_f_65_66E),
      age_56_65M = sum_moe(c(
        0.8 * age_m_55_59M, 0.8 * age_f_55_59M,
        c_across(all_of(paste0(age_56_64_core, "M"))),
        0.5 * age_m_65_66M, 0.5 * age_f_65_66M
      )),

      age_65plusE = 0.5 * (age_m_65_66E + age_f_65_66E) +
        sum(c_across(all_of(paste0(age_67plus_vars, "E"))), na.rm = TRUE),
      age_65plusM = sum_moe(c(
        0.5 * age_m_65_66M, 0.5 * age_f_65_66M,
        c_across(all_of(paste0(age_67plus_vars, "M")))
      )),

      # Inflation Adjustments
      med_income_real = med_incomeE * adj_factor,
      med_income_real_moe = med_incomeM * adj_factor,
      med_rent_real = med_rentE * adj_factor,
      med_rent_real_moe = med_rentM * adj_factor,

      # Derived Metrics + MOEs
      pct_bachelors = (edu_bachelorsE + edu_mastersE + edu_profE + edu_phdE) / edu_totalE,
      pct_bachelors_moe = ratio_moe(
        edu_bachelorsE + edu_mastersE + edu_profE + edu_phdE,
        sum_moe(c(edu_bachelorsM, edu_mastersM, edu_profM, edu_phdM)),
        edu_totalE,
        edu_totalM
      ),
      pct_hs_or_higher = (edu_hsE + edu_hs_gedE + edu_some_collegeE + edu_some_college_2E + edu_assocE + edu_bachelorsE + edu_mastersE + edu_profE + edu_phdE) / edu_totalE,
      pct_hs_or_higher_moe = ratio_moe(
        edu_hsE + edu_hs_gedE + edu_some_collegeE + edu_some_college_2E + edu_assocE + edu_bachelorsE + edu_mastersE + edu_profE + edu_phdE,
        sum_moe(c(edu_hsM, edu_hs_gedM, edu_some_collegeM, edu_some_college_2M, edu_assocM, edu_bachelorsM, edu_mastersM, edu_profM, edu_phdM)),
        edu_totalE,
        edu_totalM
      ),
      poverty_rate = poverty_belowE / poverty_totalE,
      poverty_rate_moe = ratio_moe(poverty_belowE, poverty_belowM, poverty_totalE, poverty_totalM),
      unemployment_rate = emp_unemployedE / emp_labor_forceE,
      unemployment_rate_moe = ratio_moe(emp_unemployedE, emp_unemployedM, emp_labor_forceE, emp_labor_forceM),
      vacancy_rate = vacantE / total_unitsE,
      vacancy_rate_moe = ratio_moe(vacantE, vacantM, total_unitsE, total_unitsM),
      pct_renter = renter_occupiedE / total_unitsE,
      pct_renter_moe = ratio_moe(renter_occupiedE, renter_occupiedM, total_unitsE, total_unitsM),
      pct_owner = owner_occupiedE / total_unitsE,
      pct_owner_moe = ratio_moe(owner_occupiedE, owner_occupiedM, total_unitsE, total_unitsM),

      # Race & ethnicity composition
      pct_white = race_whiteE / race_totalE,
      pct_white_moe = ratio_moe(race_whiteE, race_whiteM, race_totalE, race_totalM),
      pct_black = race_blackE / race_totalE,
      pct_black_moe = ratio_moe(race_blackE, race_blackM, race_totalE, race_totalM),
      pct_asian = race_asianE / race_totalE,
      pct_asian_moe = ratio_moe(race_asianE, race_asianM, race_totalE, race_totalM),
      pct_hispanic = race_hispanicE / race_totalE,
      pct_hispanic_moe = ratio_moe(race_hispanicE, race_hispanicM, race_totalE, race_totalM),

      # Commuting
      pct_drive_alone = commute_drive_aloneE / commute_totalE,
      pct_drive_alone_moe = ratio_moe(commute_drive_aloneE, commute_drive_aloneM, commute_totalE, commute_totalM),
      pct_public_transit = commute_publicE / commute_totalE,
      pct_public_transit_moe = ratio_moe(commute_publicE, commute_publicM, commute_totalE, commute_totalM)
    ) |>
    mutate(
      pct_age_under18 = age_under18E / total_popE,
      pct_age_under18_moe = ratio_moe(age_under18E, age_under18M, total_popE, total_popM),
      pct_age_18_25 = age_18_25E / total_popE,
      pct_age_18_25_moe = ratio_moe(age_18_25E, age_18_25M, total_popE, total_popM),
      pct_age_26_55 = age_26_55E / total_popE,
      pct_age_26_55_moe = ratio_moe(age_26_55E, age_26_55M, total_popE, total_popM),
      pct_age_56_65 = age_56_65E / total_popE,
      pct_age_56_65_moe = ratio_moe(age_56_65E, age_56_65M, total_popE, total_popM),
      pct_age_65plus = age_65plusE / total_popE,
      pct_age_65plus_moe = ratio_moe(age_65plusE, age_65plusM, total_popE, total_popM)
    ) |>
    ungroup()
}

tract_data_processed <- process_acs(acs_raw$tract) |>
  filter(GEOID %in% property_tracts)
county_data_5yr_processed <- process_acs(acs_raw$county_5yr)
county_data_1yr_processed <- process_acs(acs_raw$county_1yr)
zcta_data_processed <- process_acs(acs_raw$zcta) |>
  filter(GEOID %in% property_zctas)
zcta_full_processed <- process_acs(acs_raw$zcta_full)
if (!is.null(county_zctas) && length(county_zctas)) {
  zcta_full_processed <- zcta_full_processed %>% filter(GEOID %in% county_zctas)
}

# 6. Classify areas (Growth/Stable/Weakening) with MOE-aware significance tests
classify_tract <- function(df) {
  if (nrow(df) == 0) return(tibble())

  start_yr <- min(df$year, na.rm = TRUE)
  end_yr <- max(df$year, na.rm = TRUE)

  df_filtered <- df |> filter(year %in% c(start_yr, end_yr))
  if (nrow(df_filtered) < 2) return(tibble())

  start <- df_filtered |> filter(year == start_yr)
  end <- df_filtered |> filter(year == end_yr)

  pop_diff <- end$total_popE - start$total_popE
  pop_diff_moe <- diff_moe(start$total_popM, end$total_popM)
  pop_change_sig <- !is.na(pop_diff_moe) && abs(pop_diff) > pop_diff_moe
  pop_cagr <- ((end$total_popE / start$total_popE)^(1 / (end_yr - start_yr))) - 1

  income_diff <- end$med_income_real - start$med_income_real
  income_diff_moe <- diff_moe(start$med_income_real_moe, end$med_income_real_moe)
  income_change_sig <- !is.na(income_diff_moe) && abs(income_diff) > income_diff_moe
  income_cagr <- ((end$med_income_real / start$med_income_real)^(1 / (end_yr - start_yr))) - 1

  vacancy_diff <- end$vacancy_rate - start$vacancy_rate
  vacancy_diff_moe <- diff_moe(start$vacancy_rate_moe, end$vacancy_rate_moe)
  vacancy_change_sig <- !is.na(vacancy_diff_moe) && abs(vacancy_diff) > vacancy_diff_moe

  classification <- case_when(
    pop_change_sig && pop_diff > 0 &&
      income_change_sig && income_cagr >= 0.01 &&
      (!vacancy_change_sig || vacancy_diff < 0) ~ "Growth",
    (pop_change_sig && pop_diff < 0) ||
      (income_change_sig && income_diff < 0) ||
      (vacancy_change_sig && vacancy_diff > 0.01) ~ "Weakening",
    TRUE ~ "Stable"
  )

  tibble(
    GEOID = unique(df$GEOID),
    classification = classification,
    pop_change = pop_diff / start$total_popE,
    pop_change_moe = pop_diff_moe / start$total_popE,
    pop_change_sig = pop_change_sig,
    income_change_real = income_diff / start$med_income_real,
    income_change_real_moe = income_diff_moe / start$med_income_real,
    income_change_sig = income_change_sig,
    vacancy_change = vacancy_diff,
    vacancy_change_moe = vacancy_diff_moe,
    vacancy_change_sig = vacancy_change_sig,
    pop_cagr = pop_cagr,
    income_cagr = income_cagr,
    start_year = start_yr,
    end_year = end_yr
  )
}

tract_classifications <- tract_data_processed |>
  group_by(GEOID) |>
  group_split() |>
  map_dfr(classify_tract)
zcta_classifications <- zcta_data_processed |>
  group_by(GEOID) |>
  group_split() |>
  map_dfr(classify_tract)
zcta_full_classifications <- zcta_full_processed |>
  group_by(GEOID) |>
  group_split() |>
  map_dfr(classify_tract)

# 7. Variable dictionary for transparency in the white paper
variable_dictionary <- tribble(
  ~metric, ~description, ~source,
  "med_income_real", "Inflation-adjusted median household income (2023 $)", "ACS B19013 (5-year) + CPI-U",
  "med_rent_real", "Inflation-adjusted median gross rent (2023 $)", "ACS B25064 (5-year) + CPI-U",
  "pct_renter", "Renter share of occupied housing units", "ACS B25003",
  "vacancy_rate", "Share of vacant housing units", "ACS B25002",
  "pct_bachelors", "Population 25+ with bachelor's or higher", "ACS B15003",
  "poverty_rate", "Population below poverty line", "ACS B17001",
  "unemployment_rate", "Unemployment rate (pop 16+ in labor force)", "ACS B23025",
  "pct_public_transit", "Share of commuters using public transit", "ACS B08301",
  "age buckets", "Custom age buckets (<18, 18–25, 26–55, 56–65, 65+)", "ACS B01001 with proportional allocation",
  "race/ethnicity", "Race & ethnicity composition (non-Hispanic where applicable)", "ACS B03002",
  "classification", "Growth/Stable/Weakening based on significant 10-year changes", "Tract-level panel"
)

# 8. Merge Everything
final_data <- list(
  properties = properties_financials,
  property_reference = properties_financials,
  property_crosswalk = property_crosswalk,
  tract_counts = tract_counts,
  zcta_counts = zcta_counts,
  county_counts = county_counts,
  tract_history = tract_data_processed,
  county_history_5yr = county_data_5yr_processed,
  county_history_1yr = county_data_1yr_processed,
  zcta_history = zcta_data_processed,
  zcta_history_full = zcta_full_processed,
  tract_classifications = tract_classifications,
  zcta_classifications = zcta_classifications,
  zcta_classifications_full = zcta_full_classifications,
  variable_dictionary = variable_dictionary
)

write_rds(final_data, "data/processed/final_analytical_data.rds")
message("Data Processing Complete. Saved to data/processed/final_analytical_data.rds")
