# scripts/02_fetch_acs_data.R
library(tidyverse)
library(tidycensus)
library(sf)

# Load API Key
if(file.exists(".env")) readRenviron(".env")

# 1. Identify Target Geographies
properties <- read_rds("data/processed/property_master_list.rds")

# Extract unique Counties and Tracts
# Note: 'geographies' column from tidygeocoder is a list. 
# We need to extract the FIPS codes. 
# Since we used 'census' method, we might have FIPS in the returned columns or need to spatial join.
# Let's check if we have FIPS. If not, we use the lat/lon to get them.

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

# Check if we need to spatial join (if no FIPS columns in input)
# The previous CSV view didn't show explicit FIPS columns like 'GEOID' in the top level, 
# but tidygeocoder's 'census' method usually returns them in a nested list or specific columns.
# To be safe and robust, we'll do the spatial join.
message("Spatially joining properties to Census Tracts...")
properties_sf <- get_fips_from_latlon(properties)

target_tracts <- unique(properties_sf$GEOID)
target_counties <- unique(properties_sf$COUNTYFP) # This is just the 3-digit code
# We need full FIPS for county fetching (State + County)
target_counties_full <- unique(paste0("01", properties_sf$COUNTYFP)) # AL is 01

message(paste("Found", length(target_tracts), "unique tracts and", length(target_counties), "unique counties."))

# 2. Define Variables
# B01003_001: Total Population
# B19013_001: Median Household Income
# B25003_002: Owner Occupied
# B25003_003: Renter Occupied
# B25004_001: Vacancy Status (Total Vacant? No, B25002_003 is Vacant)
# B25002_001: Total Housing Units
# B25002_002: Occupied
# B25002_003: Vacant
# B25064_001: Median Gross Rent

acs_vars <- c(
  total_pop = "B01003_001",
  med_income = "B19013_001",
  total_units = "B25002_001",
  occupied = "B25002_002",
  vacant = "B25002_003",
  renter_occupied = "B25003_003",
  owner_occupied = "B25003_002",
  med_rent = "B25064_001"
)

# 3. Fetch Data Function
fetch_acs_data <- function(years, geography, survey = "acs5") {
  map_dfr(years, function(yr) {
    message(paste("Fetching", survey, yr, "..."))
    tryCatch({
      get_acs(
        geography = geography,
        variables = acs_vars,
        state = "AL",
        year = yr,
        survey = survey,
        output = "wide"
      ) %>% 
        mutate(year = yr, survey = survey)
    }, error = function(e) {
      message(paste("Error fetching", yr, ":", e$message))
      return(NULL)
    })
  })
}

# 4. Execute Fetches
years_5yr <- 2013:2022 # 2023 might be available, check?
# ACS 5-year 2018-2022 is the latest standard as of late 2023/early 2024. 
# 2023 1-year is out. 2023 5-year might be out (released Dec 2024?). 
# Let's try up to 2023 and see if it fails (tryCatch handles it).

message("Fetching Tract Data (5-Year)...")
tract_data <- fetch_acs_data(2013:2023, "tract", "acs5") %>% 
  filter(GEOID %in% target_tracts)

message("Fetching County Data (5-Year)...")
county_data_5yr <- fetch_acs_data(2013:2023, "county", "acs5") %>% 
  filter(GEOID %in% target_counties_full)

message("Fetching County Data (1-Year)...")
county_data_1yr <- fetch_acs_data(2013:2023, "county", "acs1") %>% 
  filter(GEOID %in% target_counties_full)

# 5. Save Raw Data
write_rds(list(
  tract = tract_data,
  county_5yr = county_data_5yr,
  county_1yr = county_data_1yr,
  properties_sf = properties_sf
), "data/processed/acs_raw_data.rds")

message("ACS Data Collection Complete.")
