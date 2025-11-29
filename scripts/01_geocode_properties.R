# scripts/01_geocode_properties.R
library(tidyverse)
library(pdftools)
library(tidygeocoder)
library(sf)

if(file.exists(".env")) readRenviron(".env")

# 1. Extract Addresses from PDF
pdf_path <- "docs/Obelisk Portfolio Values.pdf"
if(!file.exists(pdf_path)) stop("PDF not found!")

raw_text <- pdf_text(pdf_path) %>% 
  str_split("\n") %>% 
  unlist()

# Regex to find lines starting with a number, capturing text before the first '$'
# Example: "1    9645 9th Ave N                    $69,611"
properties_df <- tibble(raw_line = raw_text) %>% 
  filter(str_detect(raw_line, "^\\s*\\d+\\s+")) %>% 
  filter(!str_detect(raw_line, "(?i)beds|baths")) %>% # Exclude description lines 
  mutate(
    # Extract address part: everything after the initial number/space and before the first $
    address_raw = str_extract(raw_line, "(?<=^\\s{0,10}\\d{1,3}\\s{1,20}).*?(?=\\s*\\$)") %>% str_trim()
  ) %>% 
  filter(!is.na(address_raw)) %>% 
  slice(1:33) %>% # Strictly keep the first 33 properties from the main table
  # Clean up and add City/State context
  mutate(
    city = case_when(
      str_detect(address_raw, "(?i)Midfield") ~ "Midfield",
      str_detect(address_raw, "(?i)Ensley") ~ "Birmingham", # Ensley is a neighborhood
      TRUE ~ "Birmingham"
    ),
    state = "AL",
    # Remove city names from the street address if they are at the end to avoid duplication
    street_address = str_remove(address_raw, ",? (Midfield|Ensley)$") %>% str_trim(),
    full_address = paste(street_address, city, state, sep = ", ")
  )

message(paste("Extracted", nrow(properties_df), "properties."))

# 2. Geocode (Census API)
# We need Lat/Lon and Census Tract
message("Geocoding properties...")

geocoded_df <- properties_df %>% 
  geocode(
    street = street_address, 
    city = city, 
    state = state, 
    method = 'census', 
    full_results = TRUE
  )

# 3. Validation & Fallback
# Check for failures
failed <- geocoded_df %>% filter(is.na(lat))
if(nrow(failed) > 0) {
  message("Warning: ", nrow(failed), " properties failed to geocode with Census API.")
  print(failed$full_address)
  
  # Optional: Try OSM for failures (less reliable for Tracts, but gets Lat/Lon)
  # For now, we will just warn.
}

# 4. Convert to SF and Get Tract FIPS (if not returned directly, we can spatial join)
# Census geocoder usually returns FIPS. Let's check 'geographies.Census Tracts.GEOID' columns if available,
# but tidygeocoder's 'census' method structure can vary.
# A more robust way is to use the Lat/Lon to query the Tiger/Line shapefiles via `tigris` if needed,
# but let's save the raw geocoded result first.

# Save
write_rds(geocoded_df, "data/processed/property_master_list.rds")
write_csv(geocoded_df, "data/processed/property_master_list.csv")

message("Geocoding complete. Saved to data/processed/property_master_list.rds")
