"""
sources.py
----------
Every data source this project pulls from — verified against live APIs.

NYC: Socrata (data.cityofnewyork.us)
LA:  Socrata (data.lacity.org) — dataset ID requires verification, see note below
MD:  Aggregate only publicly available; individual-level via Maryland Judiciary
DC:  No public individual-level API — use aggregate + FOIA

IMPORTANT — What we learned from auditing the real APIs:

  NYC has TWO confirmed working datasets:
    7479-ugqb  Daily Inmates In Custody (no bail field — status code only)
    94ri-3ium  Inmate Discharges (booking + discharge dates, top charge)
  Neither includes bail amount. Bail data requires either:
    - NYC Criminal Court bulk data (available via court records request)
    - NYC BOC monthly reports (aggregate, PDF)

  The bail gap analysis uses median_daily_income from Census + bail amounts
  from court records. Where bail amount is missing, we flag the row and
  still compute detention length, charge type, and pretrial status.

  LA / MD individual-level booking datasets are not publicly available
  via Socrata in the form originally expected. The Vera Institute county
  CSV IS verified and provides the aggregate analysis backbone.

Column mappings below reflect actual field names from the live NYC API.
"""

import os
from dataclasses import dataclass, field


@dataclass
class SocrataSource:
    name: str
    jurisdiction: str
    base_url: str
    dataset_id: str
    date_field: str
    description: str
    token_env_var: str
    # Maps raw API column names → our schema column names
    column_map: dict = field(default_factory=dict)
    limit: int = 50_000
    extra_params: dict = field(default_factory=dict)

    @property
    def app_token(self) -> str:
        return os.environ.get(self.token_env_var, "")

    @property
    def endpoint(self) -> str:
        return f"{self.base_url}/{self.dataset_id}.json"


@dataclass
class DCSource:
    """
    DC does not publish individual-level jail records via public API.
    DC DOC publishes aggregate population counts via their website.
    For individual-level analysis: file a FOIA with DC DOC.
    This class is retained for the aggregate endpoint.
    """
    name: str = "DC DOC Population (Aggregate)"
    jurisdiction: str = "DC"
    # DC DOC posts aggregate snapshots — no individual booking records public API
    endpoint: str = "https://doc.dc.gov/page/population-statistics"
    date_field: str = "report_date"
    description: str = (
        "DC DOC aggregate population data. "
        "DC abolished cash bail for most offenses in 1992. "
        "Individual-level records require FOIA request to DC DOC. "
        "See docs/SOURCES.md for FOIA instructions."
    )
    page_size: int = 1000

    @property
    def base_params(self) -> dict:
        return {
            "where": "1=1",
            "outFields": "*",
            "f": "json",
            "resultOffset": 0,
            "resultRecordCount": self.page_size,
        }


DC_SOURCE = DCSource()


# ── Verified Socrata Sources ──────────────────────────────────────────────────
# Dataset IDs and column maps confirmed against live API responses.

SOCRATA_SOURCES: list[SocrataSource] = [

    # ── NEW YORK CITY — Daily Inmates In Custody ──────────────────────────────
    # Dataset ID: 7479-ugqb (VERIFIED — returns live data as of 2026-04-26)
    # Columns confirmed: inmateid, admitted_dt, custody_level, bradh, race,
    #                    gender, age, inmate_status_code, sealed, srg_flg,
    #                    top_charge, infraction
    # NOTE: No bail_amount field. Detention status inferred from inmate_status_code:
    #   DE  = Detained (pretrial, no bail paid)
    #   CS  = Sentenced (post-conviction)
    #   DEP = Detained, pending hearing
    #   DPV = Detained, parole violation
    #   SSR = State-sentenced remand
    #   DNS = Detained, no status
    SocrataSource(
        name="NYC Daily Inmates In Custody",
        jurisdiction="NYC",
        base_url="https://data.cityofnewyork.us/resource",
        dataset_id="7479-ugqb",
        date_field="admitted_dt",
        token_env_var="NYC_APP_TOKEN",
        description=(
            "Live daily snapshot of every person in NYC DOC custody — "
            "Rikers Island and the borough detention centers. "
            "Confirmed active as of 2026-04-26. No bail amount field; "
            "pretrial status derived from inmate_status_code."
        ),
        column_map={
            "inmateid":           "inmate_id",
            "admitted_dt":        "booking_date",
            "race":               "race_ethnicity",
            "gender":             "gender",
            "age":                "age",
            "inmate_status_code": "detention_status_code",
            "top_charge":         "charge_code_raw",
            "custody_level":      "custody_level",
            "infraction":         "infraction_flag",
            "sealed":             "sealed_flag",
        },
    ),

    # ── NEW YORK CITY — Inmate Discharges ─────────────────────────────────────
    # Dataset ID: 94ri-3ium (VERIFIED)
    # Columns: inmateid, admitted_dt, discharged_dt, race, gender, age,
    #          inmate_status_code, top_charge
    # Use this to calculate actual detention length for people who have been released.
    SocrataSource(
        name="NYC Inmate Discharges",
        jurisdiction="NYC",
        base_url="https://data.cityofnewyork.us/resource",
        dataset_id="94ri-3ium",
        date_field="admitted_dt",
        token_env_var="NYC_APP_TOKEN",
        description=(
            "NYC DOC discharge records — admission date, discharge date, top charge. "
            "Join to daily inmates on inmateid to get full detention timeline. "
            "Confirmed active as of 2026-04-26."
        ),
        column_map={
            "inmateid":           "inmate_id",
            "admitted_dt":        "booking_date",
            "discharged_dt":      "release_date",
            "race":               "race_ethnicity",
            "gender":             "gender",
            "age":                "age",
            "inmate_status_code": "detention_status_code",
            "top_charge":         "charge_code_raw",
        },
    ),

    # ── LOS ANGELES ───────────────────────────────────────────────────────────
    # LA County Sheriff does not expose individual booking records via public
    # Socrata API. The datasets found (hf8e-sig8, qvxz-irr8) returned 404.
    # Options:
    #   1. LASD Open Data: https://lasd.socrata.com — requires account
    #   2. LA County data requests: https://data.lacounty.gov
    #   3. ACLU of Southern California has filed for this data under California PRA
    # This entry is a placeholder — update dataset_id when a working source is found.
    SocrataSource(
        name="LA County Jail — PENDING VERIFICATION",
        jurisdiction="LA",
        base_url="https://data.lacity.org/resource",
        dataset_id="NEEDS_VERIFICATION",
        date_field="booking_date",
        token_env_var="LA_APP_TOKEN",
        description=(
            "LA County individual booking records. "
            "Public API not confirmed — see docs/SOURCES.md for alternatives. "
            "This source will be skipped if dataset_id is not updated."
        ),
        column_map={},
    ),

    # ── MARYLAND ──────────────────────────────────────────────────────────────
    # Maryland does not publish individual-level pretrial booking records via
    # public Socrata API. Available public data is aggregate ADP by county.
    # Options for individual-level:
    #   1. Maryland Judiciary Case Search: casesearch.courts.state.md.us
    #      (bulk access requires agreement with Maryland Judiciary)
    #   2. Maryland Public Information Act (MPIA) request to DPSCS
    #   3. Vera Institute county data provides aggregate trends 1970-present
    SocrataSource(
        name="MD Jail Data — AGGREGATE ONLY",
        jurisdiction="MD",
        base_url="https://opendata.maryland.gov/resource",
        dataset_id="NEEDS_VERIFICATION",
        date_field="year",
        token_env_var="MD_APP_TOKEN",
        description=(
            "Maryland individual booking records not available via public API. "
            "Use Vera Institute county CSV for aggregate MD analysis. "
            "For individual-level: file MPIA request with DPSCS. "
            "See docs/SOURCES.md for exact request language."
        ),
        column_map={},
    ),
]


# ── Verified Downloadable Sources ─────────────────────────────────────────────
# These are confirmed accessible. Download manually into data/raw/.

DOWNLOADABLE_SOURCES = [
    {
        "name": "Vera Institute — County Incarceration Trends",
        "jurisdiction": "ALL",
        "url": "https://raw.githubusercontent.com/vera-institute/incarceration-trends/master/incarceration_trends_county.csv",
        "local_path": "data/raw/vera_county.csv",
        "format": "CSV — direct download, no login",
        "verified": True,
        "key_columns": [
            "year", "county_fips", "county_name", "state_abbr",
            "total_jail_pop", "total_pretrial_custody",
            "black_jail_pop", "latinx_jail_pop", "white_jail_pop",
            "jail_rated_capacity", "total_sentenced_custody",
            "urbanicity",
        ],
        "what_it_proves": (
            "County-level jail population 1970–2022. "
            "The long arc of mass incarceration. Racial breakdown. "
            "Pretrial vs. sentenced. This is the backbone of the "
            "historical and comparative analysis."
        ),
        "load_function": "etl/vera_loader.py:load_vera_county",
    },
    {
        "name": "Vera Institute — State Incarceration Trends",
        "jurisdiction": "ALL",
        "url": "https://raw.githubusercontent.com/vera-institute/incarceration-trends/master/incarceration_trends_state.csv",
        "local_path": "data/raw/vera_state.csv",
        "format": "CSV — direct download, no login",
        "verified": True,
        "key_columns": ["year", "state_abbr", "total_jail_pop", "total_pretrial_custody"],
        "what_it_proves": "State-level trends. Compare MD pre/post 2017 reform at aggregate level.",
        "load_function": "etl/vera_loader.py:load_vera_state",
    },
    {
        "name": "Marshall Project — Deaths in Custody",
        "jurisdiction": "ALL",
        "url": "https://github.com/themarshallproject/doj-dca-data",
        "local_path": "data/raw/marshall_deaths.csv",
        "format": "CSV — clone repo or download directly",
        "verified": True,
        "key_columns": ["facility", "death_date", "manner_of_death", "conviction_status", "age", "race"],
        "what_it_proves": "Who died in custody and how. Includes pretrial deaths.",
        "load_function": "psql COPY into stg_deaths_in_custody",
    },
]


# ── FOIA / Records Request Templates ─────────────────────────────────────────
# For jurisdictions without public APIs, these are the paths to individual-level data.

FOIA_TEMPLATES = {
    "LA": (
        "Request to: LA County Sheriff's Department, Public Records Act Requests\n"
        "Request: All booking records from [DATE] to [DATE] including: booking date, "
        "release date, charges, bail amount set, bail paid (Y/N), facility, "
        "race, gender, age, and home ZIP code. Exclude name and DOB.\n"
        "Authority: California Public Records Act (Gov. Code § 7920 et seq.)"
    ),
    "MD": (
        "Request to: MD Department of Public Safety and Correctional Services\n"
        "Request: Pretrial detention records from [DATE] to [DATE] including: "
        "booking date, release date, charges, bail amount set, bail type, "
        "facility, race, gender, age, and home ZIP code. Exclude name and DOB.\n"
        "Authority: Maryland Public Information Act (GP § 4-101 et seq.)"
    ),
    "DC": (
        "Request to: DC Department of Corrections, FOIA Officer\n"
        "Request: Individual detention records from [DATE] to [DATE] including: "
        "booking date, release date, charges, hold type, facility, race, gender, "
        "age, and home ZIP code. Exclude name and DOB.\n"
        "Authority: DC Freedom of Information Act (DC Code § 2-531 et seq.)"
    ),
}
