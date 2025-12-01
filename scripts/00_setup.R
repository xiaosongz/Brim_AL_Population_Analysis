# scripts/00_setup.R
# Environment setup and dependency installation for demographic analysis pipeline

# 1. Define Package Dependencies -------------------------------------------------
# Core packages for data manipulation, spatial analysis, and Census data access
required_packages <- c(
  "tidyverse",   # Data manipulation, visualization (ggplot2, dplyr, tidyr, etc.)
  "tidycensus",  # US Census API data retrieval
  "sf",          # Spatial data handling and analysis
  "tigris",      # Census shapefile and geographic data
  "tidygeocoder",# Address geocoding service
  "pdftools",    # PDF text extraction for property list parsing
  "targets",     # Pipeline management and reproducible workflows
  "jsonlite",    # JSON data handling and parsing
  "readxl",      # Excel file reading capabilities
  "scales",      # Data formatting and scaling utilities
  "httr"         # HTTP request handling for API calls
)

# 2. Install Missing Packages ----------------------------------------------------
# Check which packages are not installed and install them from CRAN
new_packages <- required_packages[!(required_packages %in% installed.packages()[, "Package"])]
if (length(new_packages)) {
  message("Installing missing packages: ", paste(new_packages, collapse = ", "))
  install.packages(new_packages, repos = "http://cran.us.r-project.org")
}

# 3. Load Required Packages ------------------------------------------------------
# Load all dependencies for use in subsequent scripts
lapply(required_packages, library, character.only = TRUE)

# 3b. Load Environment Variables -------------------------------------------------
# Load configuration from .env file if present (API keys, settings)
if (file.exists(".env")) readRenviron(".env")

# 4. Configure Analysis Environment -----------------------------------------------
# Set analysis options for optimal performance and reproducibility
options(tigris_use_cache = TRUE)  # Cache Census shapefiles to speed up repeated operations
options(scipen = 999)             # Disable scientific notation for cleaner output

# 5. Validate Census API Access --------------------------------------------------
# Verify that required Census API key is available for data access
if (Sys.getenv("CENSUS_API_KEY") == "") {
  message("WARNING: CENSUS_API_KEY is not set in your environment.")
  message("Please sign up for a free key at http://api.census.gov/data/key_signup.html")
  message("Then configure your environment by running: census_api_key('YOUR_KEY', install = TRUE)")
} else {
  message("Census API Key found and configured.")
}

# 6. Create Project Directory Structure -------------------------------------------
# Ensure all required directories exist for data storage and outputs
dirs <- c("data/raw", "data/processed", "outputs", "scripts")
walk(dirs, ~dir.create(., showWarnings = FALSE, recursive = TRUE))

message("Environment setup complete! Project structure and packages are ready.")
