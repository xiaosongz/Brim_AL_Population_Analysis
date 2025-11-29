White Paper Specifications

This will be a RMarkdown file that pulling data from ACS using the Tidycensus package and perform a indepth analysis of the demographic and housing trends of the properties in the portfolio using community best practices and following the tidyverse style guide. 

Demographic & Housing Trend Intelligence for Portfolio Performance Evaluation

Purpose

To quantify whether the investment portfolio is positioned in submarkets that exhibit favorable long-term fundamentals. This initiative integrates property-level performance data with U.S. Census ACS demographic and housing trends to demonstrate—empirically rather than anecdotally—how our assets align with areas showing population inflow, rising household income, stable rental demand, and improved housing occupancy.

⸻

Scope

The analysis covers all properties held by Funds 1, 2, and 3 and maps each asset to its corresponding Census geography. Time-series ACS data will be used to establish neighborhood-level demographic trajectories over the past decade and compare them with property-level operating performance.

⸻

Analytical Framework

1. Spatial Alignment

Goal: Identify the exact Census statistical area in which each property is located.
	•	Every property address is geocoded to latitude and longitude.
	•	Each coordinate pair is spatially joined to:
	•	Census Tract
	•	Census Block Group (optional, for finer granularity)
	•	These geographic identifiers become the “bridge key” to link ACS data with portfolio metrics.

Deliverable: A master property reference file containing → property ID, fund ID, address, latitude/longitude, census tract, and block group.

⸻

2. Data Collection: Neighborhood Indicators

Goal: Build a longitudinal panel of demographic and housing indicators for each census tract that contains our assets, and optionally for the full county for market context.

For each year (or rolling 5-year ACS window) the following metrics are collected:

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
	•	Growth Cluster: population inflow + income increase + improving occupancy
	•	Stable Cluster: little movement across indicators
	•	Weakening Cluster: population or income decline + rising vacancy

This provides a structural picture of the submarkets in which we operate.

⸻

4. Portfolio Performance Integration

Goal: Evaluate whether strong (or weak) neighborhood fundamentals align with asset performance.

Asset-level KPIs are aggregated to the census tract and year:
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
	•	Insights can be summarized for decision-makers in one sentence, such as:

“Our rental portfolio is overwhelmingly concentrated in rapidly improving neighborhoods, and the assets in those neighborhoods outperform the rest of the market.”

⸻

If you want, the next step can be transforming this spec into:
	•	a PowerPoint outline for LP reporting, or
	•	a technical requirements document for engineers, or
	•	a Tableau dashboard wireframe, depending on your audience.