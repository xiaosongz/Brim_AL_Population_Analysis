# scripts/02_fetch_acs_data.R
library(tidyverse)
library(tidycensus)
library(sf)

# Load API Key
if (file.exists(".env")) readRenviron(".env")

# 1. Identify Target Geographies
properties <- read_rds("data/processed/property_master_list.rds")

# Function to get FIPS from Lat/Lon if missing
get_fips_from_latlon <- function(df) {
  # Convert to SF
  sf_df <- st_as_sf(df, coords = c("long", "lat"), crs = 4326)

  # Download Tracts for AL (assuming all in AL for now, based on PDF)
  al_tracts <- tigris::tracts(state = "AL", cb = TRUE, year = 2022) %>%
    select(GEOID, COUNTYFP, TRACTCE)

  # Ensure CRS match
  sf_df <- st_transform(sf_df, st_crs(al_tracts))

  joined <- st_join(sf_df, al_tracts)
  return(joined)
}

message("Spatially joining properties to Census Tracts...")
properties_sf <- get_fips_from_latlon(properties)

target_tracts <- unique(properties_sf$GEOID)
target_counties <- unique(properties_sf$COUNTYFP)
target_counties_full <- unique(paste0("01", properties_sf$COUNTYFP)) # AL is 01

# Identify Target ZCTAs
# We can get ZCTAs from the address or spatial join.
# The address has zip codes.
target_zips <- properties$address_raw %>%
  str_extract("\\d{5}$") %>%
  unique() %>%
  na.omit()

message(paste("Found", length(target_tracts), "unique tracts,", length(target_counties), "counties, and", length(target_zips), "zips."))

# 2. Define Variables
# Expanded list for deep analysis
acs_vars <- c(
  total_pop = "B01003_001",
  med_income = "B19013_001",
  total_units = "B25002_001",
  occupied = "B25002_002",
  vacant = "B25002_003",
  renter_occupied = "B25003_003",
  owner_occupied = "B25003_002",
  med_rent = "B25064_001",

  # Age
  median_age = "B01002_001",

  # Education (Universe: Pop 25+)
  edu_total = "B15003_001",
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
  emp_unemployed = "B23025_005"
)

# 3. Fetch Data Function with Caching
fetch_acs_data <- function(years, geography, survey = "acs5") {
  map_dfr(years, function(yr) {
    # Define Cache Path
    cache_dir <- "data/raw/acs_cache"
    if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
    cache_file <- file.path(cache_dir, paste0("acs_", geography, "_", survey, "_", yr, ".rds"))

    if (file.exists(cache_file)) {
      message(paste("Loading cached", survey, yr, geography, "..."))
      return(read_rds(cache_file))
    }

    message(paste("Fetching", survey, yr, geography, "..."))
    tryCatch(
      {
        # For ZCTA, we can't filter by state in get_acs (it's national).
        # We fetch all (or use state if supported for that geo, ZCTA usually isn't)
        # Actually tidycensus supports state for ZCTA since v1.0?
        # Let's try state="AL" for all, if it fails for ZCTA we handle it.

        args <- list(
          geography = geography,
          variables = acs_vars,
          year = yr,
          survey = survey,
          output = "wide"
        )

        if (geography != "zcta") {
          args$state <- "AL"
        }

        data <- do.call(get_acs, args) %>%
          mutate(year = yr, survey = survey)

        write_rds(data, cache_file)
        return(data)
      },
      error = function(e) {
        message(paste("Error fetching", yr, ":", e$message))
        return(NULL)
      }
    )
  })
}

# 4. Execute Fetches
# Tracts (5-year)
message("Fetching Tract Data (5-Year)...")
tract_data <- fetch_acs_data(2013:2023, "tract", "acs5") %>%
  filter(GEOID %in% target_tracts)

# Counties (5-year & 1-year)
message("Fetching County Data (5-Year)...")
county_data_5yr <- fetch_acs_data(2013:2023, "county", "acs5") %>%
  filter(GEOID %in% target_counties_full)

message("Fetching County Data (1-Year)...")
county_data_1yr <- fetch_acs_data(2013:2023, "county", "acs1") %>%
  filter(GEOID %in% target_counties_full)

# ZCTAs (5-year)
# Note: ZCTA data is heavy if fetched nationally.
# We will filter immediately after fetch if we can't filter in API.
# tidycensus 'zcta' usually requires fetching all or a specific zcta list?
# get_acs(geography = "zcta", zcta = target_zips) is supported in newer versions?
# Let's try fetching specific ZCTAs if possible to save bandwidth,
# otherwise we fetch state if allowed, or national.
# Actually, for 'zcta', 'state' argument is often ignored or deprecated.
# Best approach: try passing `zcta = target_zips` if supported, else fetch all.
# We'll use a modified fetch for ZCTA to be safe.

fetch_zcta_data <- function(years) {
  map_dfr(years, function(yr) {
    cache_dir <- "data/raw/acs_cache"
    cache_file <- file.path(cache_dir, paste0("acs_zcta_acs5_", yr, ".rds"))

    if (file.exists(cache_file)) {
      message(paste("Loading cached ZCTA", yr, "..."))
      return(read_rds(cache_file))
    }

    message(paste("Fetching ZCTA", yr, "..."))
    tryCatch(
      {
        # Fetch ALL ZCTAs and filter locally
        # This is safer for API stability, though larger download.
        data <- get_acs(
          geography = "zcta",
          variables = acs_vars,
          year = yr,
          survey = "acs5",
          output = "wide"
        ) %>%
          mutate(year = yr, survey = "acs5") %>%
          filter(GEOID %in% target_zips)

        write_rds(data, cache_file)
        return(data)
      },
      error = function(e) {
        message(paste("Error fetching ZCTA", yr, ":", e$message))
        return(NULL)
      }
    )
  })
}

message("Fetching ZCTA Data (5-Year)...")
zcta_data <- fetch_zcta_data(2013:2023)

# 5. Save Raw Data
write_rds(list(
  tract = tract_data,
  county_5yr = county_data_5yr,
  county_1yr = county_data_1yr,
  zcta = zcta_data,
  properties_sf = properties_sf
), "data/processed/acs_raw_data.rds")

message("ACS Data Collection Complete.")
