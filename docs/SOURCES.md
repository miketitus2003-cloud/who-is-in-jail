# Data Sources

> Every source here was verified against the live API or repository as of 2026-04-26.
> Where a source turned out to be unavailable, the alternatives and FOIA paths are documented.
> No fake dataset IDs. No assumed availability. What's here is real.

---

## What the API Audit Found

Before writing any code that runs against real data, every source was tested.
Here is what actually exists vs. what was originally assumed:

| Jurisdiction | Individual Records | Bail Amount | Home ZIP | Status |
|---|---|---|---|---|
| NYC | YES (Socrata) | NO (not in open data) | NO | Active, 2 datasets verified |
| LA | UNCERTAIN | UNKNOWN | UNKNOWN | Public API not confirmed |
| DC | NO public API | N/A | N/A | Requires FOIA |
| MD | NO public API | N/A | N/A | Requires MPIA request |

**The bail amount gap is the most important finding.**
NYC publishes who is in jail but not what bail was set.
That data lives in criminal court records, not the DOC open data portal.
The pipeline handles this transparently — bail gap is NULL where data is missing,
not fabricated or silently omitted.

---

## Confirmed Active Sources

### NYC — Daily Inmates In Custody
- **Dataset ID:** `7479-ugqb` (VERIFIED 2026-04-26 — returns live data)
- **Portal:** data.cityofnewyork.us
- **Updated:** Daily
- **Confirmed columns:**
  ```
  inmateid, admitted_dt, custody_level, bradh, race, gender,
  age, inmate_status_code, sealed, srg_flg, top_charge, infraction
  ```
- **Pretrial status:** Derived from `inmate_status_code`:
  - `DE` = Detained pretrial (legally innocent, bail not paid)
  - `DEP` = Detained, pending hearing
  - `DNS` = Detained, no status
  - `CS` = Sentenced (post-conviction)
  - `SSR` = State-sentenced remand
  - `DPV` = Detained, parole violation
- **What's missing:** Bail amount, home ZIP, facility name. These require court records.
- **Get a token:** data.cityofnewyork.us/profile/app_tokens (free, instant)

### NYC — Inmate Discharges
- **Dataset ID:** `94ri-3ium` (VERIFIED 2026-04-26)
- **Portal:** data.cityofnewyork.us
- **Confirmed columns:** `inmateid, admitted_dt, discharged_dt, race, gender, age, inmate_status_code, top_charge`
- **Use:** Join to Daily Inmates on `inmateid` to get full detention timeline.
  `discharged_dt - admitted_dt` = actual days detained.
- **Note:** Records go back to ~2018. Earlier data needs separate FOIL request.

### Vera Institute — County Incarceration Trends
- **URL:** `github.com/vera-institute/incarceration-trends`
- **File:** `incarceration_trends_county.csv` (VERIFIED — direct download works)
- **Download:** `python etl/vera_loader.py --download`
- **Coverage:** Every US county, 1970–2022
- **Confirmed columns include:**
  ```
  year, county_fips, county_name, state_abbr, urbanicity,
  total_jail_pop, total_pretrial_custody, total_sentenced_custody,
  black_jail_pop, latinx_jail_pop, white_jail_pop,
  jail_rated_capacity, total_jail_admits, total_jail_discharges
  ```
- **Why this matters:** The individual booking APIs only go back a few years.
  Vera goes back to 1970. This is how you show the long arc —
  how we built our way to mass incarceration over 50 years.
  It also gives aggregate MD pre/post 2017 reform data at the county level.

---

## Sources Requiring Verification or Access

### LA County — Individual Booking Records
- **Status:** Public Socrata datasets tested returned 404. No confirmed working endpoint.
- **Alternatives:**
  1. **LASD Open Data Portal:** `lasd.socrata.com` — requires account creation
  2. **LA County Data Portal:** `data.lacounty.gov` — check for LASD booking datasets
  3. **California DOJ:** `openjustice.doj.ca.gov` — has arrest and booking data by county
  4. **ACLU of Southern California** has litigated for this data under the California PRA
- **California PRA request language:**
  ```
  To: Los Angeles County Sheriff's Department, Records Bureau
  Request: All booking records from [DATE] to [DATE] including: booking date,
  release date, top charge, bail amount set, bail paid (Y/N), facility,
  race, gender, age, and home ZIP code. Exclude name and DOB.
  Authority: California Public Records Act (Gov. Code § 7920 et seq.)
  ```

### Maryland — Individual Booking Records
- **Status:** No public individual-level API confirmed. `opendata.maryland.gov`
  publishes aggregate ADP (average daily population) by facility, not individual records.
- **Aggregate data available:**
  - Vera county CSV covers Baltimore City (FIPS 24510) and PG County (FIPS 24033)
  - Use `python etl/vera_loader.py --load` to see MD county trends 1970–2022
- **For individual records — Maryland MPIA request:**
  ```
  To: MD Department of Public Safety and Correctional Services, Public Information Act Officer
  Request: Individual pretrial detention records from [DATE] to [DATE] including:
  booking date, release date, charges filed, bail amount set, bail type
  (cash/bond/ROR/remand), facility, race, gender, age, and home ZIP code.
  Exclude name and date of birth.
  Authority: Maryland Public Information Act (GP § 4-101 et seq.)
  Response required within 10 business days (GP § 4-203).
  ```
- **Maryland Judiciary Case Search:** `casesearch.courts.state.md.us`
  Has individual case outcomes. Bulk access requires a data agreement with the MD Judiciary.
  Contact: mdcourts.gov/courtoperations/dataandstatistics

### Washington DC — Individual Booking Records
- **Status:** No public individual-level API. DC DOC publishes aggregate
  population snapshots on their website, not individual bookings.
- **Why DC matters:** DC abolished cash bail for most offenses in 1992.
  It is the control group — a jurisdiction that shows what justice can look like
  without cash bail. The aggregate numbers matter here.
- **DC aggregate data:** `doc.dc.gov/page/population-statistics` (PDF reports)
- **For individual records — DC FOIA:**
  ```
  To: DC Department of Corrections, FOIA Officer
  Request: Individual detention records from [DATE] to [DATE] including:
  booking date, release date, charges, hold type, facility,
  race, gender, age, and home ZIP code. Exclude name and DOB.
  Authority: DC Freedom of Information Act (DC Code § 2-531 et seq.)
  Response required within 15 business days.
  ```

---

## NYC Bail Data — The Gap and How to Fill It

NYC open data does not publish bail amounts. Here is how to get them:

### Option 1: NYC Criminal Court Bulk Data
- **Contact:** NYCourts.gov — Office of Court Administration
- **Request:** Criminal court arraignment data including docket number, charges,
  bail set amount, bail type, and disposition.
- **Precedent:** The Legal Aid Society and other public defenders have received this data.

### Option 2: NYC Office of Criminal Justice (MOCJ)
- **Contact:** nyc.gov/criminaljustice
- **They publish:** Some aggregate bail statistics in annual reports.
- **What you get:** Not individual records, but city-level bail set vs. paid rates.

### Option 3: Scrape NYC Criminal Court eCourts
- **URL:** `iapps.courts.state.ny.us/webcrim_attorney/DefendantSearch`
- **Legality:** Public records, but bulk scraping may violate terms of service.
  Use with care and at low volume.

### Option 4: Use Vera + Published Research
The Vera Institute's Bail Trap report (2017) and Arnold Foundation research
include NYC-specific bail amount data. Cite these for the analysis, note
the year, and be transparent that open data doesn't publish bail amounts directly.

---

## Conditions Data

### NYC Board of Correction — Monthly Statistics
- **URL:** nyc.gov/site/boc/reports/monthly-statistics.page
- **Format:** PDF and Excel, published monthly
- **What it shows:** Deaths in custody, use of force, solitary confinement population,
  capacity vs. daily census at each NYC DOC facility.
- **Load process:** Manual download → parse with pandas `read_excel()` →
  `psql COPY` into `stg_deaths_in_custody`

### Marshall Project — Deaths in Custody
- **URL:** github.com/themarshallproject/doj-dca-data
- **Format:** CSV, direct download from GitHub
- **Confirmed accessible:** Yes (repo public, file exists)
- **Load:** `psql -d jail_data -c "\copy stg_deaths_in_custody FROM 'data/raw/marshall_deaths.csv' CSV HEADER"`

### Bureau of Justice Statistics — Deaths in Custody Reporting Program
- **URL:** bjs.ojp.gov/data-collection/deaths-custody-reporting-program-dcrp
- **Format:** Excel download, requires free BJS account
- **Compare to Marshall Project:** The gap between these two numbers is itself a finding.
  Many jurisdictions do not report to BJS or report incomplete data.

---

## Census ACS — Socioeconomic Context

### US Census ACS 5-Year Estimates
- **API:** `api.census.gov/data/2022/acs/acs5`
- **Free key:** `api.census.gov/sign-up.html` (instant approval)
- **Variables used:** See `etl/census.py` for complete list with descriptions
- **Coverage note:** Not all jail intake ZIP codes map cleanly to Census ZCTAs.
  Rural or PO Box ZIPs may not have ACS data. Coverage is logged during pipeline run.

### Eviction Lab — Princeton University
- **URL:** evictionlab.org/get-the-data/
- **Format:** CSV, requires free registration
- **What it shows:** Eviction rates by ZIP code — the housing-to-jail pipeline
- **Key columns:** `zip, eviction_rate, eviction_filing_rate, low_income_renter_pct`

---

## A Note on What This Means for the Analysis

The individual booking API gap (no bail amounts in NYC open data, no individual
records for LA/DC/MD) does not break the project. It focuses it.

**What we can do with confirmed data:**
- Who is in custody right now in NYC (daily snapshot)
- How long they were detained (discharge records)
- What they were charged with (top_charge field = NY Penal Law code)
- Racial and age breakdown of detained population
- Historical trends 1970–2022 for all four jurisdictions (Vera)
- Conditions: deaths, overcrowding, use of force (BOC reports, Marshall Project)
- MD aggregate pre/post 2017 reform (Vera county data)

**What requires FOIA/additional data:**
- Bail amounts (needed for the work-days-to-bail calculation)
- Home ZIP codes (needed for Census income join)
- Individual LA / DC / MD records

The project is honest about this. The FOIA templates are in `etl/sources.py`.
The analysis runs on what exists, notes where data is missing, and points to
exactly how to fill the gaps.
