# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an R-based demographic and housing trend analysis system for real estate portfolio evaluation in Jefferson County, Alabama. It integrates U.S. Census American Community Survey (ACS) data with property-level information to quantify submarket fundamentals and portfolio positioning using longitudinal demographic analysis with proper statistical treatment of ACS margins of error.

## Critical Architecture Principles

### Sequential Data Pipeline

The project follows a strict sequential ETL pipeline enforced by numbered scripts:

1. **00_setup.R** → Installs dependencies, validates Census API key, creates directories
2. **01_geocode_properties.R** → Extracts addresses from PDF, geocodes to lat/lon, spatially joins Census geographies (tract, block group, ZCTA)
3. **02_fetch_acs_data.R** → Fetches ACS data with intelligent caching system
4. **03_process_data.R** → Derives inflation-adjusted metrics, handles MOE propagation, classifies tracts
5. **reports/white_paper.Rmd** → Generates analytical HTML report

**CRITICAL**: Each script depends on outputs from prior steps. Never run scripts out of order.

### Data Geography Hierarchy

Properties are spatially linked to Census statistical areas:
- **Census Tract** (`tract_geoid`) — Primary analysis unit for neighborhood-level trends
- **Block Group** (`bg_geoid`) — Finer granularity (optional)
- **ZCTA** (`zcta5`) — ZIP Code Tabulation Area for market context
- **County** (`county_fips`) — Jefferson County (FIPS: 01073) for benchmarking

### ACS Data Best Practices (MANDATORY)

This codebase follows Census Bureau statistical guidance rigorously:

1. **Margins of Error (MOE)**: All ACS estimates include MOEs; never ignore them
   - Variables ending in `E` are estimates (e.g., `total_popE`)
   - Variables ending in `M` are margins of error (e.g., `total_popM`)
   - Use MOE helper functions: `sum_moe()`, `ratio_moe()`, `diff_moe()`

2. **Inflation Adjustment**: Income and rent variables MUST be adjusted to constant 2023 dollars using CPI-U annual averages in `cpi_table`

3. **Statistical Significance**: Treat changes as meaningful only when they exceed MOE thresholds (~90% confidence); see `classify_tract()` function

4. **Survey Consistency**: Use ACS 5-year estimates for tract-level analysis (less sampling noise than 1-year); 1-year used only for county context

### Tract Classification Logic

Tracts are classified into three categories based on statistically significant 10-year changes:

- **Growth**: Population inflow + real income growth ≥1%/year + stable/falling vacancy
- **Weakening**: Population decline OR income decline OR vacancy increase ≥1pp
- **Stable**: No significant changes across key indicators

Classification respects ACS uncertainty by requiring `abs(change) > change_moe`.

## Environment Setup

### Prerequisites
- R ≥ 4.2
- Census API key (required): [Sign up](http://api.census.gov/data/key_signup.html)
- Source PDF: `docs/Obelisk Portfolio Values.pdf` (33 properties)

### Environment Variables
Create `.env` file in project root:
```
CENSUS_API_KEY=your_census_api_key_here
REFRESH_ACS=false  # Set to "true" to force fresh ACS downloads (ignores cache)
```

### Initial Setup
```r
Rscript scripts/00_setup.R
```

This installs: tidyverse, tidycensus, sf, tigris, tidygeocoder, pdftools, targets, jsonlite, readxl, scales, httr

## Development Workflow

### Full Pipeline Execution
```bash
# 1. Setup (one-time or when dependencies change)
Rscript scripts/00_setup.R

# 2. Geocode properties from PDF
Rscript scripts/01_geocode_properties.R

# 3. Fetch ACS data (uses cache unless REFRESH_ACS=true)
Rscript scripts/02_fetch_acs_data.R

# 4. Process metrics and classifications
Rscript scripts/03_process_data.R

# 5. Render white paper
Rscript -e "rmarkdown::render('reports/white_paper.Rmd', output_dir = 'outputs')"
```

### Iterative Development

**When modifying ACS variables**:
1. Edit `acs_vars` vector in `scripts/02_fetch_acs_data.R`
2. Set `REFRESH_ACS=true` in `.env` (or run with cache override)
3. Re-run scripts 02 → 03 → render

**When changing classification logic**:
1. Edit `classify_tract()` function in `scripts/03_process_data.R`
2. Re-run scripts 03 → render (no need to re-fetch ACS data)

**When updating report visualizations**:
1. Modify `reports/white_paper.Rmd`
2. Re-render only (data already processed)

### Cache Management

ACS data is cached in `data/raw/acs_cache/` with filenames like `acs_tract_acs5_2022.rds`.

**To refresh specific year**: Delete cache file and re-run script 02
**To refresh all ACS data**: Set `REFRESH_ACS=true` in `.env`
**To inspect cache**: Check row counts with `scripts/check_cache_rows.R`

## Key Data Artifacts

### Intermediate Outputs
- `data/processed/property_master_list.rds` — Geocoded properties with Census identifiers
- `data/processed/acs_raw_data.rds` — Raw ACS data (tract, county, ZCTA levels)
- `data/processed/final_analytical_data.rds` — Processed panel dataset with classifications

### Final Deliverables
- `outputs/white_paper.html` — Executive-ready analytical report with maps, trends, insights
- Report includes: spatial maps, time-series charts, tract classifications, variable dictionary

## Code Style and Conventions

**Follow tidyverse style**:
- Use `<-` for assignment (not `=`)
- snake_case for all object and file names
- Pipe with `|>` (native pipe) or `%>%` (magrittr)
- 2-space indentation

**Functional patterns**:
- Prefer pure functions over side effects
- Use `map_dfr()` for iteration returning data frames
- Keep pipelines linear and readable; avoid deep nesting

**Explicit joins**:
```r
# GOOD
properties |> left_join(tract_data, by = c("tract_geoid" = "GEOID"))

# AVOID
properties |> left_join(tract_data)  # implicit join keys are fragile
```

**Documentation**:
- Add comments only for non-obvious logic (e.g., MOE propagation formulas, age bucket allocations)
- Keep outputs in `data/processed/` or `outputs/` (both git-ignored)

## Validation and QA

**No formal unit tests**; validate via end-to-end execution:

1. **Geocoding validation**: Check console output for failed geocodes in script 01; re-geocode manually if needed
2. **Data completeness**: Verify expected row counts:
   - `property_master_list.rds`: 33 properties
   - `tract_data`: ~10-20 unique tracts × 10 years
   - `final_analytical_data.rds`: Check `tract_classifications` has all property tracts
3. **ACS cache consistency**: When `REFRESH_ACS=false`, verify console shows "Loading cached..." messages
4. **Classification sanity**: Spot-check tract classifications align with income/vacancy trends

**Debug scripts** (in `scripts/` but not part of pipeline):
- `debug_zcta_fetch.R` — Troubleshoot ZCTA data issues
- `test_zcta_state.R` — Validate ZCTA state filtering
- `check_cache_rows.R` — Inspect cache file row counts
- `debug_cols.R` — Check column names in processed data

## White Paper Specifications

See `docs/White Paper Specifications.md` for full analytical framework.

**Key deliverables**:
- Spatial master table: Every property with Census identifiers
- Census trend panel: Longitudinal demographic/housing data by tract
- Tract classification: Growth/Stable/Weakening clusters with significance testing
- Visualization suite: Maps, time-series charts, KPI correlations
- Technical appendix: ACS variables, MOE handling, inflation adjustments, classification rules

**Strategic narrative enabled**:
> "Across Funds 1–3, 80% of assets are located in census tracts that experienced population net inflow, rising median household income, falling vacancy rates, and stable renter demand over the past decade."

## Git Workflow

Use conventional commits:
- `feat:` — New features or capabilities
- `fix:` — Bug fixes
- `chore:` — Maintenance (dependencies, cleanup)
- `docs:` — Documentation updates

**Do not commit**:
- `.env` files (contains Census API key)
- `data/` directory (large data artifacts)
- `outputs/` directory (generated reports)
- PDF source files (`docs/*.pdf`)

All sensitive/large files are git-ignored per `.gitignore`.

## Common Pitfalls

1. **Running scripts out of order**: Each script depends on prior outputs; always run sequentially
2. **Ignoring MOEs**: Never compute derived metrics without propagating margins of error
3. **Mixing ACS survey types**: Use 5-year for tracts, 1-year only for county benchmarks
4. **Forgetting inflation adjustment**: Income/rent must be adjusted to constant dollars before trend analysis
5. **Cache staleness**: When ACS variables change, remember to set `REFRESH_ACS=true`
6. **Geocoding failures**: Always check console warnings from script 01 before proceeding

## Extending the Analysis

**Adding new ACS variables**:
1. Look up variable codes at [Census API](https://api.census.gov/data/2022/acs/acs5/variables.html)
2. Add to `acs_vars` vector in `scripts/02_fetch_acs_data.R`
3. Create derived metrics in `process_acs()` function in `scripts/03_process_data.R`
4. Update `variable_dictionary` for documentation

**Adding new classification dimensions**:
1. Modify `classify_tract()` logic in `scripts/03_process_data.R`
2. Ensure new criteria respect MOE significance tests
3. Update white paper interpretation

**Expanding to new geographies**:
1. Update `target_counties` or `target_zctas` in `scripts/02_fetch_acs_data.R`
2. Adjust spatial joins in `scripts/01_geocode_properties.R` if needed
3. Update county-level benchmarks in reporting

## Technical Notes

- **CRS**: All spatial operations use EPSG:4326 (WGS84) for consistency
- **Tigris caching**: Enabled via `options(tigris_use_cache = TRUE)` to speed up shapefile downloads
- **Age bucket allocation**: Custom buckets (<18, 18–25, 26–55, 56–65, 65+) require proportional splits of ACS 5-year age bands; see `age_*_vars` definitions in script 03
- **ZCTA fetching**: ZCTA data uses full county list derived from spatial intersection with Jefferson County boundary (not just property ZCTAs)
