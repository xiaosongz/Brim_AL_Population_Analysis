# Brim AL Population Analysis

This repository builds a demographic and housing market assessment for the Jefferson County, AL portfolio and renders the white paper HTML output.

## Prerequisites
- R ≥ 4.2 with tidyverse ecosystem, `sf`, `tigris`, `tidycensus`, `leaflet`, `rmarkdown`
- `.env` containing `CENSUS_API_KEY=<your key>`; optionally set `REFRESH_ACS=true` to force new ACS pulls
- `docs/Obelisk Portfolio Values.pdf` present (input for geocoding)

## Pipeline (scripts)
Run these from the repo root:

1) Install deps and create directories  
```sh
Rscript scripts/00_setup.R
```
2) Parse the portfolio PDF, geocode properties, and build `data/processed/property_master_list.*`  
```sh
Rscript scripts/01_geocode_properties.R
```
3) Pull ACS data (cached in `data/raw/acs_cache`; uses cache unless `REFRESH_ACS=true`) and write `data/processed/acs_raw_data.rds`  
```sh
Rscript scripts/02_fetch_acs_data.R
```
4) Process metrics, apply MOE-aware classifications, and output `data/processed/final_analytical_data.rds`  
```sh
Rscript scripts/03_process_data.R
```
5) Render the white paper HTML to `outputs/white_paper.html`  
```sh
Rscript -e "rmarkdown::render('reports/white_paper.Rmd', output_dir = 'outputs')"
```

## Data flow
```
docs/Obelisk Portfolio Values.pdf
            │
            ▼
scripts/01_geocode_properties.R
            │  → geocoded properties
            ▼
data/processed/property_master_list.rds
            │
            ├── scripts/02_fetch_acs_data.R (tidycensus)
            │       │
            │       ├→ data/raw/acs_cache/ (ACS cache)
            │       ▼
            │   data/processed/acs_raw_data.rds
            │
            └── scripts/03_process_data.R
                    │
                    ▼
        data/processed/final_analytical_data.rds
                    │
                    ▼
        reports/white_paper.Rmd → outputs/white_paper.html
```

## Notes and tips
- Default ACS coverage: tract/ZCTA 5-year (2013–2022) and county 1-year (2013–2023). Set `REFRESH_ACS=true` to refresh cache when new vintages are released.
- Outputs in `data/` and `outputs/` are git-ignored by design; keep tracked changes to code and docs only.
- After refreshing ACS data, rerun steps 3–5 to regenerate `final_analytical_data.rds` and the report.*** End Patch" ***!
