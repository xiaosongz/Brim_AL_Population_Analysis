White Paper Specifications

This white paper will be generated as an beautiful and stylish R Markdown report that pulls data from the American Community Survey (ACS) using the `tidycensus` package and performs an in‑depth analysis of the demographic and housing trends of the properties in the portfolio, following community best practices and the tidyverse style guide. 

Demographic & Housing Trend Intelligence for Portfolio Performance Evaluation

Purpose

To quantify whether the investment portfolio is positioned in submarkets that exhibit favorable long-term fundamentals. This initiative integrates property-level performance data with U.S. Census ACS demographic and housing trends to demonstrate—empirically rather than anecdotally—how our assets align with areas showing population inflow, rising household income, stable rental demand, and improved housing occupancy.

⸻

Scope

The analysis covers all properties held by Funds 1, 2, and 3 and maps each asset to its corresponding Census geography. Time-series ACS data will be used to establish neighborhood-level demographic trajectories over the past decade and compare them with property-level operating performance.

Data Sources & Time Horizon

The core inputs are:
	•	Property portfolio data, including the Obelisk Portfolio – Cost & Equity Snapshot (33 properties such as 9645 9th Ave N, 4129 Avenue Q, 4011 43rd Ave N, etc.), with acquisition cost, renovation cost, total cost, Sy’s fair-market value, equity, and ROI tier.
	•	ACS 5-year estimates (e.g., 2013–2017 through 2019–2023) at the census tract level, retrieved via `tidycensus::get_acs`, with both point estimates and Census-provided margins of error stored for each variable.
	•	County-level ACS aggregates for context and benchmarking.

Where possible, income- and rent-related variables will be inflation-adjusted to constant dollars so trends represent real (not nominal) change.

⸻

Analytical Framework

1. Spatial Alignment

Goal: Identify the exact Census statistical area in which each property is located.
	•	Every property address is geocoded to latitude and longitude.
	•	Geocoding uses a consistent provider (e.g., the Census geocoder or a commercial API) with manual QA for ambiguous or low-confidence matches.
	•	Each coordinate pair is spatially joined to:
	•	Census Tract
	•	Census Block Group (optional, for finer granularity)
	•	These geographic identifiers become the “bridge key” to link ACS data with portfolio metrics.

Deliverable: A master property reference file containing → property ID, fund ID, address, latitude/longitude, census tract, and block group.

⸻

2. Data Collection: Neighborhood Indicators

Goal: Build a longitudinal panel of demographic and housing indicators for each census tract that contains our assets, and optionally for the full county for market context.

For each reference year (using ACS 5-year estimates retrieved via `tidycensus::get_acs`) the following metrics are collected, along with their margins of error:

Demographics
	•	Total population
	•	Age distribution (custom buckets: <18, 18–25, 26–55, 56–65, 65+)
	•	Race & ethnicity composition

Socioeconomic
	•	Median household income
	•	Poverty rate
	•	Educational attainment (% high school or higher; % bachelor’s or higher)
	•	Commuting/transportation modes

Housing Market Indicators
	•	Tenure mix (renters vs. owners)
	•	Vacancy rate
	•	Median rent
	•	Indicators of rental cost burden (optional)

Best-practice handling of ACS data:
	•	Track and retain ACS margins of error for all estimates; use `tidycensus` MOE helpers (e.g., `moe_sum`, `moe_prop`, `moe_ratio`) when deriving new indicators from base variables, following Census Bureau guidance.
	•	Inflation-adjust income- and rent-related variables to constant dollars (e.g., using CPI or BEA price indices) so time-series trends reflect real changes in purchasing power.
	•	Avoid mixing ACS 1-year and 5-year products for the same analysis; use a consistent 5-year series for tract-level comparisons to reduce sampling noise.

Outcome: A tract-level longitudinal dataset representing neighborhood change over time.

⸻

3. Trend & Classification Analysis

Goal: Determine whether the census tracts containing our assets are improving, stagnating, or declining across relevant dimensions.

Each tract is labeled according to directional change over the decade:

Dimension	Signals of Momentum	Signals of Risk
Population	Sustained inflow	Decline
Income	Rising median household income	Stagnation or erosion
Housing demand	Rising renter share + falling vacancy	Softening rental demand
Education	Rising attainment	Declining attainment
Median rent	Increasing in line with income	Decoupling from income / affordability stress

A tract may be classified into interpretive clusters such as:
	•	Growth Cluster: population inflow + income increase + improving occupancy (e.g., positive 10-year population CAGR, real median income growth ≥ ~1% annually, and falling vacancy)
	•	Stable Cluster: little movement across indicators (e.g., all core indicators within approximately ±0.5% annual change and close to county medians)
	•	Weakening Cluster: population or income decline + rising vacancy (e.g., population CAGR ≤ −0.5% or vacancy rate increase ≥ ~1 percentage point, especially with flat or declining real income)

Classification should respect ACS uncertainty: treat changes as “rising” or “declining” only when they are statistically distinguishable from zero at approximately the 90% confidence level, using ACS margins of error and standard Census Bureau testing guidance.

This provides a structural picture of the submarkets in which we operate.

⸻

4. Portfolio Performance Integration

Goal: Evaluate whether strong (or weak) neighborhood fundamentals align with asset performance.

Asset-level KPIs are aggregated to the census tract and year:
	•	Capital structure variables from the Obelisk Portfolio – Cost & Equity Snapshot (acquisition cost, renovation cost, total cost, Sy’s fair-market value, equity, and property-level ROI tier)
	•	Average achieved rent
	•	Rent growth
	•	Average vacancy duration
	•	Renewal rate / tenant retention
	•	Delinquency (optional)
	•	Maintenance cost per occupied unit (optional)

These KPIs are compared against neighborhood demographic and housing trends:

Example dimensions of comparison
	•	Do properties in tracts with growing income show higher rent growth?
	•	Do tracts with declining population show higher vacancy durations?
	•	Are renewal rates systematically higher in “High-Momentum” tracts?
	•	Are outliers caused by property management decisions or structural market conditions?

The objective is to determine how much of asset performance is driven by macro neighborhood fundamentals vs micro execution factors.

⸻

Strategic Narrative Enabled by the Analysis

This framework enables a new level of investor communication:

Instead of

“We believe these areas are strong rental markets.”

We can state:

“Across Funds 1–3, 80% of assets are located in census tracts that experienced population net inflow, rising median household income, falling vacancy rates, and stable renter demand over the past decade. In these same tracts, our assets demonstrated higher rent growth and shorter vacancy periods than county benchmarks.”

And conversely, if underperforming assets are found in declining demographic submarkets, the insight is equally valuable:

“The few assets with prolonged vacancy are located in tracts classified as ‘Weakening Cluster,’ characterized by population decline and rising vacancy rates. These findings inform disposition and future acquisition targeting.”

⸻

Final Deliverables

Output Type	Description
Spatial master table	Every property with census identifiers
Census trend panel	Longitudinal demographic & housing data by tract
Performance overlay panel	Tract-year dataset combining ACS + asset KPIs
Tract classification	Growth / Stable / Weakening clusters with logic
Visualization suite	Maps, time-series charts, KPI correlations
Executive-ready narrative	Data-driven story of submarket positioning and portfolio strength
Technical appendix	ACS variables, time horizon, MOE handling, inflation adjustments, and tract classification rules


⸻

Use Cases
	1.	Investor Relations / LP Reporting
	•	Defensible narrative of disciplined geographic concentration
	2.	Acquisition Strategy
	•	Identify high-momentum submarkets where fundamentals signal future appreciation
	3.	Portfolio Optimization
	•	Highlight assets lagging purely due to neighborhood deterioration
	4.	Disposition Strategy
	•	Data-driven rationale for exit from weakening submarkets

⸻

Success Criteria

The project is considered successful when:
	•	Every property is precisely located within the census statistical geography.
	•	A unified tract-year panel dataset exists for ACS + asset KPIs.
	•	Neighborhood trends can be quantitatively linked to operating performance.
	•	ACS variables, MOE handling, inflation adjustments, and tract classification thresholds are fully documented and reproducible.
	•	Insights can be summarized for decision-makers in one sentence, such as:

“Our rental portfolio is overwhelmingly concentrated in rapidly improving neighborhoods, and the assets in those neighborhoods outperform the rest of the market.”

⸻

If you want, the next step can be transforming this spec into:
	•	a PowerPoint outline for LP reporting, or
	•	a technical requirements document for engineers, or
	•	a Tableau dashboard wireframe, depending on your audience.
