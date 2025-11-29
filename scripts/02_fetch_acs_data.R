# scripts/02_fetch_acs_data.R
library(tidyverse)
library(tidycensus)
library(sf)

if (file.exists(".env")) readRenviron(".env")
options(tigris_use_cache = TRUE)

# 1. Identify Target Geographies from the property reference file
properties <- read_rds("data/processed/property_master_list.rds")
refresh_acs <- tolower(Sys.getenv("REFRESH_ACS", "false")) %in% c("true", "1", "yes")

target_tracts <- properties$tract_geoid |> na.omit() |> unique()
target_counties <- properties$county_fips |> na.omit() |> unique()
target_counties_full <- properties |>
  filter(!is.na(county_fips)) |>
  mutate(state_fips = ifelse(is.na(state_fips), "01", state_fips)) |>
  transmute(county_geoid = paste0(state_fips, county_fips)) |>
  distinct() |>
  pull(county_geoid)
target_zctas <- properties$zcta5 |> coalesce(properties$zip) |> na.omit() |> unique()

message(paste("Found", length(target_tracts), "unique tracts,", length(target_counties), "counties, and", length(target_zctas), "zctas/zips."))

# 2. Define Variables aligned with the white paper spec (demographics, housing, socioeconomics)
acs_vars <- c(
  total_pop = "B01003_001",
  med_income = "B19013_001",
  total_units = "B25002_001",
  occupied = "B25002_002",
  vacant = "B25002_003",
  renter_occupied = "B25003_003",
  owner_occupied = "B25003_002",
  med_rent = "B25064_001",
  median_age = "B01002_001",

  # Age buckets (male)
  age_m_under5 = "B01001_003",
  age_m_5_9 = "B01001_004",
  age_m_10_14 = "B01001_005",
  age_m_15_17 = "B01001_006",
  age_m_18_19 = "B01001_007",
  age_m_20 = "B01001_008",
  age_m_21 = "B01001_009",
  age_m_22_24 = "B01001_010",
  age_m_25_29 = "B01001_011",
  age_m_30_34 = "B01001_012",
  age_m_35_39 = "B01001_013",
  age_m_40_44 = "B01001_014",
  age_m_45_49 = "B01001_015",
  age_m_50_54 = "B01001_016",
  age_m_55_59 = "B01001_017",
  age_m_60_61 = "B01001_018",
  age_m_62_64 = "B01001_019",
  age_m_65_66 = "B01001_020",
  age_m_67_69 = "B01001_021",
  age_m_70_74 = "B01001_022",
  age_m_75_79 = "B01001_023",
  age_m_80_84 = "B01001_024",
  age_m_85_plus = "B01001_025",

  # Age buckets (female)
  age_f_under5 = "B01001_027",
  age_f_5_9 = "B01001_028",
  age_f_10_14 = "B01001_029",
  age_f_15_17 = "B01001_030",
  age_f_18_19 = "B01001_031",
  age_f_20 = "B01001_032",
  age_f_21 = "B01001_033",
  age_f_22_24 = "B01001_034",
  age_f_25_29 = "B01001_035",
  age_f_30_34 = "B01001_036",
  age_f_35_39 = "B01001_037",
  age_f_40_44 = "B01001_038",
  age_f_45_49 = "B01001_039",
  age_f_50_54 = "B01001_040",
  age_f_55_59 = "B01001_041",
  age_f_60_61 = "B01001_042",
  age_f_62_64 = "B01001_043",
  age_f_65_66 = "B01001_044",
  age_f_67_69 = "B01001_045",
  age_f_70_74 = "B01001_046",
  age_f_75_79 = "B01001_047",
  age_f_80_84 = "B01001_048",
  age_f_85_plus = "B01001_049",

  # Race & ethnicity (composition)
  race_total = "B03002_001",
  race_white = "B03002_003",
  race_black = "B03002_004",
  race_asian = "B03002_006",
  race_other = "B03002_007",
  race_two_or_more = "B03002_008",
  race_hispanic = "B03002_012",

  # Education (Universe: Pop 25+)
  edu_total = "B15003_001",
  edu_hs = "B15003_017",
  edu_hs_ged = "B15003_018",
  edu_some_college = "B15003_019",
  edu_some_college_2 = "B15003_020",
  edu_assoc = "B15003_021",
  edu_bachelors = "B15003_022",
  edu_masters = "B15003_023",
  edu_prof = "B15003_024",
  edu_phd = "B15003_025",

  # Poverty (Universe: Population for whom poverty status is determined)
  poverty_total = "B17001_001",
  poverty_below = "B17001_002",

  # Employment (Universe: Pop 16+)
  emp_total = "B23025_001",
  emp_labor_force = "B23025_002",
  emp_unemployed = "B23025_005",

  # Commuting/transportation
  commute_total = "B08301_001",
  commute_drive_alone = "B08301_003",
  commute_carpool = "B08301_004",
  commute_public = "B08301_010",
  commute_other = "B08301_019"
)

# 3. Fetch Data Function with Caching (5-year ACS for tract-level comparisons)
years <- 2013:2022
years_acs1 <- setdiff(2013:2023, 2020) # include latest 1-year (2023), exclude experimental 2020

fetch_acs_data <- function(years, geography, survey = "acs5", state = NULL, zcta = NULL) {
  map_dfr(years, function(yr) {
    cache_dir <- "data/raw/acs_cache"
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    cache_file <- file.path(cache_dir, paste0("acs_", geography, "_", survey, "_", yr, ".rds"))

    if (!refresh_acs && file.exists(cache_file)) {
      message(paste("Loading cached", survey, yr, geography, "..."))
      return(read_rds(cache_file))
    }

    message(paste("Fetching", survey, yr, geography, "..."))
    args <- list(
      geography = geography,
      variables = acs_vars,
      year = yr,
      survey = survey,
      output = "wide"
    )

    if (!is.null(state)) args$state <- state
    if (!is.null(zcta)) args$zcta <- zcta

    data <- tryCatch(
      do.call(get_acs, args),
      error = function(e) {
        message(paste("Error fetching", yr, geography, ":", e$message))
        return(tibble())
      }
    )

    if (is.null(data) || nrow(data) == 0) return(tibble())

    data <- data |> mutate(year = yr, survey = survey)
    write_rds(data, cache_file)
    data
  })
}

# 4. Execute Fetches
message("Fetching Tract Data (5-Year, ACS)...")
tract_data <- fetch_acs_data(years, "tract", "acs5", state = "AL") |>
  filter(GEOID %in% target_tracts)

message("Fetching County Data (5-Year, ACS)...")
county_data_5yr <- fetch_acs_data(years, "county", "acs5", state = "AL") |>
  filter(GEOID %in% target_counties_full)

message("Fetching County Data (1-Year, ACS) for context only...")
county_data_1yr <- fetch_acs_data(years_acs1, "county", "acs1", state = "AL") |>
  filter(GEOID %in% target_counties_full)

message("Fetching ZCTA Data (5-Year, ACS)...")
fetch_zcta_data <- function(years, target_zctas) {
  if (length(target_zctas) == 0) return(tibble())

  map_dfr(years, function(yr) {
    cache_dir <- "data/raw/acs_cache"
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    cache_file <- file.path(cache_dir, paste0("acs_zcta_acs5_", yr, ".rds"))

    if (!refresh_acs && file.exists(cache_file)) {
      message(paste("Loading cached ZCTA", yr, "..."))
      return(read_rds(cache_file))
    }

    message(paste("Fetching ZCTA", yr, "..."))
    data <- tryCatch(
      get_acs(
        geography = "zcta",
        variables = acs_vars,
        year = yr,
        survey = "acs5",
        output = "wide",
        zcta = target_zctas
      ),
      error = function(e) {
        message("ZCTA-specific fetch failed for year ", yr, "; performing full national download then filtering.")
        tryCatch(
          get_acs(
            geography = "zcta",
            variables = acs_vars,
            year = yr,
            survey = "acs5",
            output = "wide"
          ),
          error = function(e2) {
            message(paste("Error fetching ZCTA", yr, ":", e2$message))
            return(tibble())
          }
        )
      }
    )

    if (is.null(data) || nrow(data) == 0) return(tibble())

    data <- data |>
      mutate(year = yr, survey = "acs5")

    if (length(target_zctas)) {
      data <- dplyr::filter(data, GEOID %in% target_zctas)
    }

    write_rds(data, cache_file)
    data
  })
}

zcta_data <- fetch_zcta_data(years, target_zctas)

# 5. Save Raw Data
write_rds(
  list(
    tract = tract_data,
    county_5yr = county_data_5yr,
    county_1yr = county_data_1yr,
    zcta = zcta_data,
    properties = properties
  ),
  "data/processed/acs_raw_data.rds"
)

message("ACS Data Collection Complete.")
