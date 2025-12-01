# scripts/01_geocode_properties.R
# Extract property addresses from PDF and geocode to Census geographic units

# Load required libraries --------------------------------------------------------
library(tidyverse)    # Data manipulation and tidyr functions
library(pdftools)     # PDF text extraction capabilities
library(tidygeocoder) # Address geocoding using Census API
library(sf)           # Spatial data handling and operations
library(tigris)       # Census shapefile and geographic data

# Configure environment ----------------------------------------------------------
if (file.exists(".env")) readRenviron(".env")  # Load environment variables
options(tigris_use_cache = TRUE)               # Cache Census shapefiles for speed

# 1. Extract Property Addresses from PDF ----------------------------------------
# Parse the property portfolio PDF to extract addresses and financial information
pdf_path <- "docs/Obelisk Portfolio Values.pdf"
if (!file.exists(pdf_path)) {
  stop("PDF not found at ", pdf_path,
       ". Please ensure the property portfolio file is in the docs/ directory.")
}

# Extract all text content from PDF and split into individual lines
raw_text <- pdf_text(pdf_path) |>
  str_split("\n") |>
  unlist()

# Parse property data using regex patterns to identify property table rows
# Pattern matches lines starting with numbers followed by property address info
# Example: "1    9645 9th Ave N                    $69,611"
properties_df <- tibble(raw_line = raw_text) |>
  filter(str_detect(raw_line, "^\\s*\\d+\\s+")) |>  # Keep numbered lines
  filter(!str_detect(raw_line, "(?i)beds|baths")) |> # Exclude description headers
  mutate(
    # Extract address text between line number and first dollar sign
    address_raw = str_extract(
      raw_line,
      "(?<=^\\s{0,10}\\d{1,3}\\s{1,20}).*?(?=\\s*\\$)"
    ) |> str_trim()
  ) |>
  filter(!is.na(address_raw)) |>                  # Keep lines with valid addresses
  slice(1:33) |>                                  # Limit to first 33 properties
  mutate(
    # Standardize city names based on address patterns
    city = case_when(
      str_detect(address_raw, "(?i)Midfield") ~ "Midfield",
      str_detect(address_raw, "(?i)Ensley") ~ "Birmingham", # Ensley is Birmingham neighborhood
      TRUE ~ "Birmingham"
    ),
    state = "AL",                                # All properties in Alabama
    # Extract street address portion (remove city suffix if present)
    street_address = str_remove(address_raw, ",? (Midfield|Ensley)$") |> str_trim(),
    # Create full formatted address for geocoding
    full_address = paste(street_address, city, state, sep = ", "),
    # Add sequential property ID for tracking
    property_id = row_number()
  )

message("Successfully extracted ", nrow(properties_df), " properties from PDF.")

# 2. Geocode Property Addresses Using Census API ---------------------------------
# Convert addresses to geographic coordinates (latitude/longitude)
message("Geocoding property addresses using Census API...")

geocoded_df <- properties_df |>
  geocode(
    street = street_address,
    city = city,
    state = state,
    method = "census",           # Use Census Bureau's geocoding service
    full_results = TRUE          # Return detailed match information
  )

# 3. Validate Geocoding Results --------------------------------------------------
# Check for any failed geocoding attempts and report issues
failed_geocodes <- geocoded_df |>
  filter(is.na(lat))

if (nrow(failed_geocodes) > 0) {
  message("Warning: ", nrow(failed_geocodes),
          " properties failed to geocode with Census API:")
  print(failed_geocodes$full_address)
  message("These properties will need manual address verification or geocoding.")
}

# 4. Attach Census Geographic Identifiers ---------------------------------------
# Perform spatial joins to link properties to Census geographic units
properties_sf <- geocoded_df |>
  mutate(
    # Create geocode quality indicator from match results
    geocode_quality = paste(match_indicator, match_type, sep = ":"),
    # Extract ZIP code from matched address or original address
    zip = coalesce(
      str_extract(matched_address, "\\d{5}$"),
      str_extract(full_address, "\\d{5}$")
    )
  ) |>
  # Convert to spatial object using longitude/latitude coordinates
  st_as_sf(coords = c("long", "lat"), crs = 4326, remove = FALSE)

# Download Census boundary shapefiles for spatial joins
tracts_al <- tracts(state = "AL", cb = TRUE, year = 2022, class = "sf") |>
  select(tract_geoid = GEOID, county_fips = COUNTYFP, state_fips = STATEFP)

block_groups_al <- block_groups(state = "AL", cb = TRUE, year = 2022, class = "sf") |>
  select(bg_geoid = GEOID)

zctas_al <- zctas(cb = TRUE, year = 2020, class = "sf") |>
  select(zcta5 = ZCTA5CE20)

# Perform spatial joins to attach all geographic identifiers
properties_geo <- properties_sf |>
  st_transform(st_crs(tracts_al)) |>  # Align coordinate systems
  st_join(tracts_al, join = st_within, left = TRUE) |>       # Join to census tracts
  st_join(block_groups_al, join = st_within, left = TRUE) |> # Join to block groups
  st_join(zctas_al, join = st_within, left = TRUE) |>         # Join to ZCTAs
  mutate(
    # Handle cases where tract missing but block group available
    tract_geoid <- ifelse(
      is.na(tract_geoid) & !is.na(bg_geoid),
      str_sub(bg_geoid, 1, 11),
      tract_geoid
    ),
    # Derive county FIPS from tract if missing
    county_fips <- ifelse(
      is.na(county_fips) & !is.na(tract_geoid),
      str_sub(tract_geoid, 1, 5),
      county_fips
    ),
    # Default to Alabama state FIPS if missing
    state_fips <- ifelse(is.na(state_fips), "01", state_fips)
  )

# Create final property reference table with all relevant information
property_reference <- properties_geo |>
  st_drop_geometry() |>  # Remove spatial geometry for storage
  select(
    property_id,           # Sequential property identifier
    id,                    # Geocoding service ID
    address_raw,           # Original address from PDF
    street_address,        # Standardized street address
    city,                  # City name
    state,                 # State abbreviation
    zip,                   # ZIP code
    full_address,          # Complete formatted address
    lat,                   # Latitude coordinate
    long,                  # Longitude coordinate
    geocode_quality,       # Geocoding match quality indicator
    tract_geoid,           # Census tract GEOID
    bg_geoid,              # Census block group GEOID
    county_fips,           # County FIPS code
    state_fips,            # State FIPS code
    zcta5,                 # ZIP Code Tabulation Area
    raw_line               # Original text line from PDF
  )

# 5. Save Geocoded Property Data ------------------------------------------------
# Store results for use in subsequent analysis steps
write_rds(property_reference, "data/processed/property_master_list.rds")
write_csv(property_reference, "data/processed/property_master_list.csv")

message("Geocoding complete! Property master list saved to data/processed/")
