# scripts/01_geocode_properties.R
library(tidyverse)
library(pdftools)
library(tidygeocoder)
library(sf)
library(tigris)

if (file.exists(".env")) readRenviron(".env")
options(tigris_use_cache = TRUE)

# 1. Extract Addresses from PDF
pdf_path <- "docs/Obelisk Portfolio Values.pdf"
if (!file.exists(pdf_path)) stop("PDF not found!")

raw_text <- pdf_text(pdf_path) |>
  str_split("\n") |>
  unlist()

# Regex to find lines starting with a number, capturing text before the first '$'
# Example: "1    9645 9th Ave N                    $69,611"
properties_df <- tibble(raw_line = raw_text) |>
  filter(str_detect(raw_line, "^\\s*\\d+\\s+")) |>
  filter(!str_detect(raw_line, "(?i)beds|baths")) |> # Exclude description lines 
  mutate(
    address_raw = str_extract(raw_line, "(?<=^\\s{0,10}\\d{1,3}\\s{1,20}).*?(?=\\s*\\$)") |> str_trim()
  ) |>
  filter(!is.na(address_raw)) |>
  slice(1:33) |> # Strictly keep the first 33 properties from the main table
  mutate(
    city = case_when(
      str_detect(address_raw, "(?i)Midfield") ~ "Midfield",
      str_detect(address_raw, "(?i)Ensley") ~ "Birmingham", # Ensley is a neighborhood
      TRUE ~ "Birmingham"
    ),
    state = "AL",
    street_address = str_remove(address_raw, ",? (Midfield|Ensley)$") |> str_trim(),
    full_address = paste(street_address, city, state, sep = ", "),
    property_id = row_number()
  )

message(paste("Extracted", nrow(properties_df), "properties."))

# 2. Geocode (Census API)
# We need Lat/Lon and Census Tract
message("Geocoding properties...")

geocoded_df <- properties_df |>
  geocode(
    street = street_address,
    city = city,
    state = state,
    method = "census",
    full_results = TRUE
  )

# 3. Validation & Fallback
failed <- geocoded_df |> filter(is.na(lat))
if (nrow(failed) > 0) {
  message("Warning: ", nrow(failed), " properties failed to geocode with Census API.")
  print(failed$full_address)
  # Optional fallback could be added for failures; for now we flag for manual QA.
}

# 4. Spatial joins to attach tract, block group, county, and ZCTA identifiers
properties_sf <- geocoded_df |>
  mutate(
    geocode_quality = paste(match_indicator, match_type, sep = ":"),
    zip = coalesce(str_extract(matched_address, "\\d{5}$"), str_extract(full_address, "\\d{5}$"))
  ) |>
  st_as_sf(coords = c("long", "lat"), crs = 4326, remove = FALSE)

tracts_al <- tracts(state = "AL", cb = TRUE, year = 2022, class = "sf") |>
  select(tract_geoid = GEOID, county_fips = COUNTYFP, state_fips = STATEFP)

block_groups_al <- block_groups(state = "AL", cb = TRUE, year = 2022, class = "sf") |>
  select(bg_geoid = GEOID)

zctas_al <- zctas(cb = TRUE, year = 2020, class = "sf") |>
  select(zcta5 = ZCTA5CE20)

properties_geo <- properties_sf |>
  st_transform(st_crs(tracts_al)) |>
  st_join(tracts_al, join = st_within, left = TRUE) |>
  st_join(block_groups_al, join = st_within, left = TRUE) |>
  st_join(zctas_al, join = st_within, left = TRUE) |>
  mutate(
    tract_geoid = ifelse(is.na(tract_geoid) & !is.na(bg_geoid), str_sub(bg_geoid, 1, 11), tract_geoid),
    county_fips = ifelse(is.na(county_fips) & !is.na(tract_geoid), str_sub(tract_geoid, 1, 5), county_fips),
    state_fips = ifelse(is.na(state_fips), "01", state_fips)
  )

property_reference <- properties_geo |>
  st_drop_geometry() |>
  select(
    property_id,
    id,
    address_raw,
    street_address,
    city,
    state,
    zip,
    full_address,
    lat,
    long,
    geocode_quality,
    tract_geoid,
    bg_geoid,
    county_fips,
    state_fips,
    zcta5,
    raw_line
  )

# Save
write_rds(property_reference, "data/processed/property_master_list.rds")
write_csv(property_reference, "data/processed/property_master_list.csv")

message("Geocoding complete. Saved to data/processed/property_master_list.rds")
