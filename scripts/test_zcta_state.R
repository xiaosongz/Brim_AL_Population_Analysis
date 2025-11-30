# scripts/test_zcta_state.R
library(tidycensus)
library(tidyverse)

if (file.exists(".env")) readRenviron(".env")

message("Testing ZCTA fetch with state argument...")
tryCatch(
    {
        data <- get_acs(
            geography = "zcta",
            variables = "B01003_001",
            state = "AL",
            year = 2013,
            survey = "acs5"
        )
        message("Fetch successful! Rows: ", nrow(data))
    },
    error = function(e) {
        message("Fetch failed: ", e$message)
    }
)
