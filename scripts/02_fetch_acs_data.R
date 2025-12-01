# scripts/02_fetch_acs_data.R
# Fetch American Community Survey data for property-related geographic areas

# Load required libraries --------------------------------------------------------
library(tidyverse)    # Data manipulation and functional programming tools
library(tidycensus)   # Census API integration for ACS data retrieval
library(sf)           # Spatial data handling and geometric operations
library(tigris)       # Census shapefile and geographic boundary data

# Configure environment ----------------------------------------------------------
if (file.exists(".env")) readRenviron(".env")  # Load environment variables
options(tigris_use_cache = TRUE)               # Cache Census shapefiles

# 1. Identify Target Geographies from Property Data -------------------------------
# Load property master list and extract unique geographic identifiers
properties <- read_rds("data/processed/property_master_list.rds")

# Check if we should refresh cached ACS data based on environment variable
refresh_acs <- tolower(Sys.getenv("REFRESH_ACS", "false")) %in% c("true", "1", "yes")

# Extract unique Census tracts containing properties
target_tracts <- properties$tract_geoid |>
  na.omit() |>
  unique()

# Extract unique county FIPS codes for properties
target_counties <- properties$county_fips |>
  na.omit() |>
  unique()

# Create full county GEOIDs (state + county FIPS) for API calls
target_counties_full <- properties |>
  filter(!is.na(county_fips)) |>
  mutate(state_fips = ifelse(is.na(state_fips), "01", state_fips)) |>
  transmute(county_geoid = paste0(state_fips, county_fips)) |>
  distinct() |>
  pull(county_geoid)

# Extract unique ZCTAs and ZIP codes from property locations
target_zctas <- properties$zcta5 |>
  coalesce(properties$zip) |>
  na.omit() |>
  unique()

# Identify all ZCTAs that intersect with Jefferson County for broader market context
jefferson_county <- tigris::counties(state = "AL", cb = TRUE, year = 2022, class = "sf") |>
  filter(GEOID %in% target_counties_full) |>
  st_transform(4326)

# Get all ZCTA geometries and find those intersecting Jefferson County
zcta_geom_full <- tigris::zctas(cb = TRUE, year = 2020, class = "sf") |>
  st_transform(4326)

# Calculate spatial intersection matrix between ZCTAs and county
inter_mat <- st_intersects(zcta_geom_full, jefferson_county, sparse = FALSE)
county_zctas <- zcta_geom_full$ZCTA5CE20[apply(inter_mat, 1, any)] |> unique()

# Use county ZCTAs for broader analysis, fall back to property ZCTAs if needed
zcta_fetch_list <- county_zctas
if (length(zcta_fetch_list) == 0) zcta_fetch_list <- target_zctas

message("Identified ", length(zcta_fetch_list), " ZCTAs in county boundary.")
message("Found ", length(target_tracts), " tracts, ",
        length(target_counties), " counties, ",
        length(target_zctas), " property ZCTAs/ZIPs.")

# 2. Define ACS Variables for Analysis -----------------------------------------
# Comprehensive set of ACS variables aligned with demographic and housing analysis
# Each variable includes both estimate (E) and margin of error (M) components
acs_vars <- c(
  # Core demographics and housing characteristics
  total_pop = "B01003_001",        # Total population
  med_income = "B19013_001",       # Median household income
  total_units = "B25002_001",      # Total housing units
  occupied = "B25002_002",         # Occupied housing units
  vacant = "B25002_003",           # Vacant housing units
  renter_occupied = "B25003_003",  # Renter-occupied units
  owner_occupied = "B25003_002",   # Owner-occupied units
  med_rent = "B25064_001",         # Median gross rent
  median_age = "B01002_001",       # Median age

  # Age distribution - male population by age groups
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

  # Age distribution - female population by age groups
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

  # Race and ethnicity composition (Hispanic origin treated separately)
  race_total = "B03002_001",
  race_white = "B03002_003",
  race_black = "B03002_004",
  race_asian = "B03002_006",
  race_other = "B03002_007",
  race_two_or_more = "B03002_008",
  race_hispanic = "B03002_012",

  # Educational attainment (population 25 years and older)
  edu_total = "B15003_001",
  edu_hs = "B15003_017",           # High school graduate
  edu_hs_ged = "B15003_018",       # High school graduate (includes GED)
  edu_some_college = "B15003_019", # Some college, less than 1 year
  edu_some_college_2 = "B15003_020", # Some college, 1+ years
  edu_assoc = "B15003_021",        # Associate degree
  edu_bachelors = "B15003_022",    # Bachelor degree
  edu_masters = "B15003_023",      # Master degree
  edu_prof = "B15003_024",         # Professional school degree
  edu_phd = "B15003_025",          # Doctorate degree

  # Poverty status (population for whom poverty status determined)
  poverty_total = "B17001_001",
  poverty_below = "B17001_002",

  # Employment status (civilian population 16 years and older)
  emp_total = "B23025_001",
  emp_labor_force = "B23025_002",  # In labor force
  emp_unemployed = "B23025_005",   # Unemployed

  # Commuting and transportation patterns
  commute_total = "B08301_001",
  commute_drive_alone = "B08301_003",
  commute_carpool = "B08301_004",
  commute_public = "B08301_010",
  commute_other = "B08301_019"
)

# 3. Define Time Periods and Caching Strategy ------------------------------------
# Define analysis time frame: 10-year period with ACS 5-year estimates
years <- 2013:2022                           # Primary analysis period (5-year ACS)
years_acs1 <- setdiff(2013:2023, 2020)      # 1-year ACS for context, excluding 2020

# 4. ACS Data Fetching Function with Intelligent Caching ------------------------
# Fetch ACS data with built-in caching to avoid repeated API calls
fetch_acs_data <- function(years, geography, survey = "acs5", state = NULL, zcta = NULL) {
  map_dfr(years, function(yr) {
    # Set up cache directory and file naming
    cache_dir <- "data/raw/acs_cache"
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    cache_file <- file.path(
      cache_dir,
      paste0("acs_", geography, "_", survey, "_", yr, ".rds")
    )

    # Check for cached data if refresh not requested
    if (!refresh_acs && file.exists(cache_file)) {
      message("Loading cached ", survey, " ", yr, " ", geography, "...")
      return(read_rds(cache_file))
    }

    # Fetch fresh data from Census API
    message("Fetching ", survey, " ", yr, " ", geography, "...")

    # Build API call arguments
    args <- list(
      geography = geography,
      variables = acs_vars,
      year = yr,
      survey = survey,
      output = "wide"
    )

    # Add geographic filters if specified
    if (!is.null(state)) args$state <- state
    if (!is.null(zcta)) args$zcta <- zcta

    # Execute API call with error handling
    data <- tryCatch(
      do.call(get_acs, args),
      error = function(e) {
        message("Error fetching ", yr, " ", geography, ": ", e$message)
        return(tibble())
      }
    )

    # Handle empty results gracefully
    if (is.null(data) || nrow(data) == 0) {
      message("No data returned for ", yr, " ", geography)
      return(tibble())
    }

    # Add metadata and cache results
    data <- data |>
      mutate(year = yr, survey = survey)

    write_rds(data, cache_file)
    data
  })
}

# 5. Execute Core Data Fetching -------------------------------------------------
# Fetch ACS data for all required geographic levels and time periods

# Primary analysis: Census tract data (5-year ACS for stability)
message("Fetching Tract Data (5-Year ACS)...")
tract_data <- fetch_acs_data(years, "tract", "acs5", state = "AL") |>
  filter(GEOID %in% target_tracts)

# County-level data for broader context (5-year ACS)
message("Fetching County Data (5-Year ACS)...")
county_data_5yr <- fetch_acs_data(years, "county", "acs5", state = "AL") |>
  filter(GEOID %in% target_counties_full)

# Additional county data for recent trends (1-year ACS where available)
message("Fetching County Data (1-Year ACS) for recent context...")
county_data_1yr <- fetch_acs_data(years_acs1, "county", "acs1", state = "AL") |>
  filter(GEOID %in% target_counties_full)

message("Fetching ZCTA Data (5-Year, ACS)...")
fetch_zcta_data <- function(years, target_zctas = NULL) {
  if (!is.null(target_zctas) && length(target_zctas) == 0) {
    return(tibble())
  }

  map_dfr(years, function(yr) {
    cache_dir <- "data/raw/acs_cache"
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    cache_file <- file.path(cache_dir, paste0("acs_zcta_acs5_", yr, ".rds"))

    if (!refresh_acs && file.exists(cache_file)) {
      cached <- read_rds(cache_file)
      # If cache is incomplete (doesn't cover requested ZCTAs), refresh
      covered <- if (is.null(target_zctas)) Inf else length(intersect(unique(cached$GEOID), target_zctas))
      if (covered >= length(unique(target_zctas %||% character()))) {
        message(paste("Loading cached ZCTA", yr, "..."))
        return(cached)
      } else {
        message(paste("Cache for ZCTA", yr, "is incomplete; refreshing."))
      }
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

    if (is.null(data) || nrow(data) == 0) {
      return(tibble())
    }

    data <- data |>
      mutate(year = yr, survey = "acs5")

    if (!is.null(target_zctas) && length(target_zctas)) {
      data <- dplyr::filter(data, GEOID %in% target_zctas)
    }

    write_rds(data, cache_file)
    data
  })
}

zcta_data <- fetch_zcta_data(years, target_zctas)

# Full county ZCTA fetch (filtered to county list)
fetch_zcta_full <- function(years, target_zctas) {
  map_dfr(years, function(yr) {
    cache_dir <- "data/raw/acs_cache"
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    cache_file <- file.path(cache_dir, paste0("acs_zcta_full_acs5_", yr, ".rds"))

    if (!refresh_acs && file.exists(cache_file)) {
      cached <- read_rds(cache_file)
      # Check coverage
      covered <- length(intersect(unique(cached$GEOID), target_zctas))
      if (covered >= length(target_zctas)) {
        message(paste("Loading cached full ZCTA", yr, "..."))
        return(cached)
      } else {
        message(paste("Cache for full ZCTA", yr, "incomplete; refreshing."))
      }
    }

    message(paste("Fetching full ZCTA for county list", yr, "..."))
    data <- tryCatch(
      get_acs(
        geography = "zcta",
        variables = acs_vars,
        year = yr,
        survey = "acs5",
        output = "wide",
        state = "AL"
      ),
      error = function(e) {
        message(paste("Error fetching full ZCTA", yr, ":", e$message))
        return(tibble())
      }
    )

    if (nrow(data) > 0) {
      data <- data %>%
        mutate(year = yr, survey = "acs5") %>%
        filter(GEOID %in% target_zctas)
      write_rds(data, cache_file)
    }
    data
  })
}

zcta_data_full <- fetch_zcta_full(years, county_zctas)

# 6. Store All ACS Data ----------------------------------------------------------
# Consolidate all fetched data into single structured RDS file for downstream processing
write_rds(
  list(
    tract = tract_data,                    # Primary tract-level analysis data
    county_5yr = county_data_5yr,          # County context (5-year estimates)
    county_1yr = county_data_1yr,          # County context (1-year estimates)
    zcta = zcta_data,                      # Property-specific ZCTA data
    zcta_full = zcta_data_full,            # County-wide ZCTA data
    properties = properties,               # Property reference data
    county_zctas = zcta_fetch_list         # List of county ZCTAs for reference
  ),
  "data/processed/acs_raw_data.rds"
)

message("ACS data collection complete! Data saved to data/processed/acs_raw_data.rds")
