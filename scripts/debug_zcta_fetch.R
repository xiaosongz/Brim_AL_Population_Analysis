# scripts/debug_zcta_fetch.R
library(tidyverse)
library(tidycensus)
library(sf)
library(tigris)

if (file.exists(".env")) readRenviron(".env")
options(tigris_use_cache = TRUE)

# 1. Identify Target Geographies
properties <- read_rds("data/processed/property_master_list.rds")

target_counties_full <- properties |>
    filter(!is.na(county_fips)) |>
    mutate(state_fips = ifelse(is.na(state_fips), "01", state_fips)) |>
    transmute(county_geoid = paste0(state_fips, county_fips)) |>
    distinct() |>
    pull(county_geoid)

message("Target Counties: ", paste(target_counties_full, collapse = ", "))

# 2. Tigris Intersection
message("Fetching Jefferson County geometry...")
jefferson_county <- tigris::counties(state = "AL", cb = TRUE, year = 2022, class = "sf") |>
    filter(GEOID %in% target_counties_full) |>
    st_transform(4326)

message("Fetching ZCTA geometry...")
zcta_geom_full <- tigris::zctas(cb = TRUE, year = 2020, class = "sf") |>
    st_transform(4326)

message("Calculating intersection...")
inter_mat <- st_intersects(zcta_geom_full, jefferson_county, sparse = FALSE)
county_zctas <- zcta_geom_full$ZCTA5CE20[apply(inter_mat, 1, any)] |> unique()

message(paste("County ZCTAs detected:", length(county_zctas)))
print(head(county_zctas))

# 3. Test Fetch
acs_vars <- c(total_pop = "B01003_001") # Minimal var for testing

message("Testing ACS fetch for detected ZCTAs...")
tryCatch(
    {
        data <- get_acs(
            geography = "zcta",
            variables = acs_vars,
            year = 2022,
            survey = "acs5",
            zcta = county_zctas
        )
        message("Fetch successful! Rows: ", nrow(data))
        print(head(data))
    },
    error = function(e) {
        message("Fetch failed: ", e$message)
    }
)
