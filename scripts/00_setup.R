# scripts/00_setup.R

# 1. Define Package Dependencies
required_packages <- c(
  "tidyverse",   # Data manipulation and plotting
  "tidycensus",  # US Census Data
  "sf",          # Spatial data handling
  "tigris",      # Census shapefiles
  "tidygeocoder",# Geocoding
  "pdftools",    # PDF text extraction (for property list)
  "targets",     # Pipeline management
  "jsonlite",    # JSON handling
  "readxl",      # Excel reading
  "scales",      # Formatting
  "httr"         # API requests
)

# 2. Install missing packages
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages)) install.packages(new_packages, repos = "http://cran.us.r-project.org")

# 3. Load Packages
lapply(required_packages, library, character.only = TRUE)

# 3b. Load Environment Variables
if(file.exists(".env")) readRenviron(".env")

# 4. Set Options
options(tigris_use_cache = TRUE)
options(scipen = 999) # Turn off scientific notation

# 5. Check for Census API Key
if (Sys.getenv("CENSUS_API_KEY") == "") {
  message("WARNING: CENSUS_API_KEY is not set in your environment.")
  message("Please sign up for a key at http://api.census.gov/data/key_signup.html")
  message("Then run: census_api_key('YOUR_KEY', install = TRUE)")
} else {
  message("Census API Key found.")
}

# 6. Create Directories (Redundant check)
dirs <- c("data/raw", "data/processed", "outputs", "scripts")
walk(dirs, ~dir.create(., showWarnings = FALSE, recursive = TRUE))

message("Setup Complete! Project structure and packages are ready.")
