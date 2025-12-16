# Investor Dashboard Implementation Notes

## Project Overview

This document captures the decision-making process and implementation journey for creating an investor dashboard from raw Excel portfolio data.

---

## 1. Initial Data Exploration

### Source File
`data/raw/Sample Dashboard_Clean V1.0.xlsx`

### First Impressions

Upon examining the Excel file, we identified two sheets with distinct purposes:

#### Sheet 1: "Sample Dashboard"
- **KPI Section**: Fund I and Fund II capital contributions totaling ~$2.835M (I.C.C.)
- **Portfolio Metrics**: 32 single-family homes with potential rent projections
- **T-12 Financial Time Series**: Monthly data from May-Oct 2025 showing:
  - Effective Gross Income (EGI)
  - Fixed Expenses
  - Variable Expenses
  - Net Operating Income (NOI)
  - Cap Rate calculations
- **Two Sensitivity Matrices**:
  - Portfolio Valuation matrix (NOI vs Cap Rate)
  - Loan Affordability matrix (Debt Service vs Interest Rate)

#### Sheet 2: "Annual Proforma"
- Template structure with 23 property addresses
- No numerical values populated (placeholder for future use)

### Key Observations
1. The data was investor-focused with clear KPI targets
2. T-12 trend data enabled time-series visualization
3. Sensitivity matrices suggested scenario analysis was important to stakeholders
4. Cap Rate = NOI / Portfolio Value relationship was central to valuation story

---

## 2. Tech Stack Decision

### Why R + Flexdashboard?

| Consideration | Decision Factor |
|---------------|-----------------|
| **Existing Project Stack** | Project already uses R for ACS demographic analysis; consistency preferred |
| **Excel Integration** | `readxl` package provides native Excel parsing |
| **Interactive Charts** | `plotly` enables hover tooltips, zoom, and dynamic exploration |
| **Dashboard Framework** | `flexdashboard` offers rapid prototyping with minimal boilerplate |
| **Static + Interactive** | Flexdashboard supports both static HTML and Shiny runtime |
| **Styling** | Bootstrap themes + custom CSS for professional appearance |

### Packages Used
```r
- flexdashboard: Dashboard layout and structure
- tidyverse: Data manipulation (dplyr, tidyr, ggplot2)
- plotly: Interactive visualizations
- scales: Number formatting (dollar, percent)
- DT: Interactive data tables
- readxl: Excel file parsing
```

### Alternative Considered
- **Python + Dash/Streamlit**: Would require separate environment; R already established
- **Tableau/Power BI**: Overkill for this scope; less version-control friendly
- **Pure Shiny**: More complexity than needed for initial dashboard

---

## 3. Dashboard Architecture

### Two-Version Strategy

We implemented two separate Rmd files to serve different use cases:

| File | Runtime | Output | Use Case |
|------|---------|--------|----------|
| `investor_dashboard.Rmd` | Static | `outputs/investor_dashboard.html` | Shareable, no server needed |
| `investor_dashboard_shiny.Rmd` | Shiny | Localhost app | Interactive calculators with sliders |

**Rationale**: Static HTML can be emailed to investors or hosted on any web server. Shiny version enables real-time scenario exploration during meetings.

### Data Pipeline

```
Excel File
    ↓
scripts/04_prepare_dashboard_data.R
    ↓
data/processed/dashboard_data.rds
    ↓
reports/investor_dashboard*.Rmd
    ↓
outputs/investor_dashboard.html (static)
    or
localhost:7654 (Shiny)
```

---

## 4. Design Iterations

### Version 1: Basic Structure
- 6 KPI value boxes
- Fund allocation pie chart
- Simple line charts for T-12 trends

### Version 2: Enhanced Visualizations
- Changed EGI breakdown from area chart to **stacked bar** for clearer expense vs NOI separation
- Added color coding: warm tones (yellow/red) for expenses, green for NOI
- Improved KPI labels to show "as of Oct 2025" for clarity

### Version 3: Scenario Analysis Heatmaps
- Initial implementation used matrix-based `add_heatmap()` - **broke rendering**
- Fixed by switching to data frame-based `plot_ly()` with `type = "heatmap"`
- Added current position (blue circle) and target position (green diamond) markers
- Connected markers with arrow to show progression path

### Version 4: Color Logic Correction
**Critical insight from user**: Higher NOI + Higher Cap Rate = GOOD (stabilized)

Original (incorrect):
- Colored by portfolio value (higher value = green)
- But higher cap rate means LOWER value mathematically

Corrected approach:
- Created "progress score" based on movement toward target
- Portfolio Valuation: `progress = (noi_norm + cap_norm) / 2`
- Loan Affordability: `affordability = (ds_norm + rate_norm_inverted) / 2`
- Color gradient: Red (starting) → Yellow (mid) → Green (target)

### Version 5: Interactive Calculators (Shiny)
**User insight**: Cap Rate should auto-calculate from NOI given fixed Portfolio Value

Calculator design:
- **Portfolio Valuation**: Single NOI slider → auto-calculates Cap Rate
- **Loan Affordability**: Two sliders (Debt Service + Interest Rate) → calculates Max Loan
- Colored result boxes that change based on progress toward targets
- Status labels: "Starting Point" → "Below Target" → "In Progress" → "Near Target" → "At Target"

---

## 5. Current Dashboard Features

### Executive Summary Page
| Component | Visualization |
|-----------|---------------|
| Total I.C.C. | Value box |
| Portfolio Units | Value box |
| 2026 Potential NOI | Value box |
| Potential Cap Rate | Value box |
| Current NOI (Oct 2025) | Value box |
| Current Cap Rate | Value box |
| Fund Allocation | Donut chart |
| T-12 Trends | Multi-line chart |
| EGI Breakdown | Stacked bar chart |
| Cap Rate Trend | Line chart with target reference |

### Scenario Analysis Page
| Component | Visualization |
|-----------|---------------|
| Portfolio Valuation | Heatmap with current/target markers |
| Loan Affordability | Heatmap with DS capacity line |
| Key Metrics Summary | Data table |
| T-12 Monthly Data | Data table |

### Calculators Page (Shiny only)
| Component | Inputs | Output |
|-----------|--------|--------|
| Portfolio Valuation | NOI slider | Cap Rate (colored) + Portfolio Value (fixed) |
| Loan Affordability | DS slider + Rate slider | Max Loan Amount (colored) |

---

## 6. Key Technical Decisions

### Heatmap Implementation
```r
# BROKEN: Matrix-based approach
plot_ly() |> add_heatmap(x = range, y = range, z = matrix)

# WORKING: Data frame approach
plot_ly(df, x = ~col1, y = ~col2, z = ~score, type = "heatmap")
```

### Color Gradient Logic
```r
# Progress score 0-1 mapped to Red-Yellow-Green
if (progress < 0.5) {
  r <- 220
  g <- round(180 * (progress * 2))
  b <- 50
} else {
  r <- round(220 - 180 * ((progress - 0.5) * 2))
  g <- 180
  b <- 50
}
```

### Shiny vs Static Separation
- `runtime: shiny` in YAML enables Shiny features but prevents static rendering
- Solution: Maintain two files; static version omits Calculators tab

---

## 7. File Structure

```
reports/
├── investor_dashboard.Rmd        # Static version (2 tabs)
├── investor_dashboard_shiny.Rmd  # Shiny version (3 tabs with calculators)
└── dashboard_styles.css          # Custom styling

scripts/
└── 04_prepare_dashboard_data.R   # Excel → RDS data extraction

data/
├── raw/
│   └── Sample Dashboard_Clean V1.0.xlsx
└── processed/
    └── dashboard_data.rds

outputs/
└── investor_dashboard.html       # Rendered static dashboard (~9MB)
```

---

## 8. Usage Instructions

### Render Static Dashboard
```r
rmarkdown::render('reports/investor_dashboard.Rmd', output_dir = 'outputs')
```

### Run Interactive Shiny Dashboard
```r
rmarkdown::run('reports/investor_dashboard_shiny.Rmd')
# Opens at http://127.0.0.1:7654
```

### Update Data
1. Replace Excel file in `data/raw/`
2. Run `Rscript scripts/04_prepare_dashboard_data.R`
3. Re-render dashboard(s)

---

## 9. Lessons Learned

1. **User domain knowledge is critical**: The color logic correction came from understanding that investors view higher cap rates positively (indicates stabilized returns)

2. **Plotly heatmaps are finicky**: Data frame approach more reliable than matrix approach

3. **Two-file strategy beats conditional logic**: Cleaner to maintain separate static/Shiny versions than complex runtime switches

4. **Auto-calculation reduces user error**: Cap Rate calculator with single NOI input prevents impossible scenarios

5. **Flexdashboard limitations**: No native slider support without Shiny runtime; acceptable trade-off for static shareability

---

## 10. Future Enhancements

- [ ] Add property-level breakdown tab
- [ ] Include historical comparison (YoY trends)
- [ ] Export scenario results to PDF
- [ ] Connect to live data source (database/API)
- [ ] Add user authentication for Shiny version

---

*Document created: December 2024*
*Last updated: December 2024*
