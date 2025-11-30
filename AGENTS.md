# Repository Guidelines

## Project Structure & Flow
- `scripts/00_setup.R` installs R dependencies and prepares directories; `01_geocode_properties.R` parses `docs/Obelisk Portfolio Values.pdf`, geocodes addresses, and builds `data/processed/property_master_list.*`; `02_fetch_acs_data.R` pulls ACS data (with caching in `data/raw/acs_cache`); `03_process_data.R` derives metrics/classifications and writes `data/processed/final_analytical_data.rds`.
- `reports/white_paper.Rmd` renders the analytical report; HTML output lives in `outputs/`.
- `docs/White Paper Specifications.md` captures the analytical spec; `data/` holds raw/processed artifacts (git-ignored).

## Setup, Build, and Run
- Ensure R (≥4.2) is installed. Set `CENSUS_API_KEY` in `.env`; optional `REFRESH_ACS=true` forces fresh ACS pulls.
- Install deps and create directories:  
  ```sh
  Rscript scripts/00_setup.R
  ```
- Geocode properties (requires PDF in `docs/`):  
  ```sh
  Rscript scripts/01_geocode_properties.R
  ```
- Fetch ACS (cached unless `REFRESH_ACS` is true):  
  ```sh
  Rscript scripts/02_fetch_acs_data.R
  ```
- Process metrics and classifications:  
  ```sh
  Rscript scripts/03_process_data.R
  ```
- Render report (writes to `outputs/white_paper.html`):  
  ```sh
  Rscript -e "rmarkdown::render('reports/white_paper.Rmd', output_dir = 'outputs')"
  ```

## Coding Style & Naming
- Follow tidyverse style: 2-space indents, `<-` for assignment, snake_case for objects/files, pipe with `|>`/`%>%`.
- Prefer pure functions and readable pipelines over deeply nested logic; keep joins keyed explicitly.
- Document non-obvious steps with brief comments; keep outputs in `data/processed` or `outputs`, not tracked files.

## Testing & Data Checks
- No formal unit tests; validate by running the script chain end-to-end. Confirm `data/processed/final_analytical_data.rds` exists and key tables (e.g., `tract_classifications`, `property_crosswalk`) have expected row counts.
- Spot-check geocode failures printed by `01_geocode_properties.R`; rerun with corrected addresses if needed.
- When refreshing ACS, verify cache reuse/refresh messages to avoid stale data.

## Commit & PR Guidelines
- Use conventional commits (`feat:`, `fix:`, `chore:`, `docs:`). Keep messages imperative and scoped (see recent history).
- PRs should summarize purpose, list scripts run, note data sources touched, and attach updated report screenshots if visuals change.
- Do not commit secrets or large data artifacts; `.env`, `data/`, and `outputs/` are intentionally git-ignored.
