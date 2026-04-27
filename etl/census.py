"""
census.py
---------
US Census ACS (American Community Survey) enrichment.

This is what makes the bail gap analysis real.
A $500 bail is nothing to someone in a wealthy ZIP code.
It is impossible for someone in a poor one.

The Census data proves that gap with real numbers —
median income, single-parent households, poverty rates —
mapped to the exact ZIP codes people were arrested in.
"""

import time
import logging
from typing import Optional

import requests
import pandas as pd

log = logging.getLogger(__name__)

import os
CENSUS_API_KEY = os.environ.get("CENSUS_API_KEY", "")

CENSUS_BASE = "https://api.census.gov/data/2022/acs/acs5"

# ACS variable codes → human-readable names
# Every variable here tells part of the story
ACS_VARIABLES = {
    # Income
    "B19013_001E": "median_household_income",
    "B17001_002E": "people_below_poverty_line",
    "B17001_001E": "poverty_universe_total",

    # Education (proxy for legal literacy — knowing your rights)
    "B15003_022E": "bachelors_degree_count",
    "B15003_001E": "education_universe_total",
    "B15003_002E": "no_schooling_count",

    # Family structure
    "B09002_002E": "children_married_couple_hh",
    "B09002_008E": "children_single_mother_hh",
    "B09002_011E": "children_single_father_hh",
    "B09002_001E": "children_total",

    # Housing instability (the pipeline to jail)
    "B25070_010E": "rent_burdened_50pct_plus",   # paying >50% income on rent
    "B25070_001E": "renter_universe_total",
    "B25002_003E": "vacant_housing_units",

    # Total population (for rate calculations)
    "B01003_001E": "total_population",

    # Race (for disparity analysis — we use this at aggregate level only)
    "B02001_002E": "white_alone",
    "B02001_003E": "black_alone",
    "B02001_004E": "native_alone",
    "B02001_005E": "asian_alone",
    "B03001_003E": "hispanic_or_latino",
}


def fetch_acs_for_zips(zip_codes: list[str], chunk_size: int = 50) -> pd.DataFrame:
    """
    Fetch ACS 5-year estimates for a list of ZIP codes (ZCTAs).

    Census API limits: 50 geographies per request.
    We chunk automatically.

    Args:
        zip_codes:   List of 5-digit ZIP codes
        chunk_size:  How many ZIPs to request at once (Census max: 50)

    Returns:
        DataFrame with one row per ZIP, all socioeconomic indicators.
    """
    if not CENSUS_API_KEY:
        log.warning(
            "No CENSUS_API_KEY in environment. "
            "Requests will be limited. Get a free key at api.census.gov/sign-up.html"
        )

    variable_str = ",".join(ACS_VARIABLES.keys())
    all_rows = []

    # Clean and deduplicate ZIPs
    clean_zips = list({str(z).strip()[:5].zfill(5) for z in zip_codes if str(z).strip()})
    log.info("Fetching Census ACS data for %d unique ZIPs...", len(clean_zips))

    for i in range(0, len(clean_zips), chunk_size):
        chunk = clean_zips[i : i + chunk_size]
        zip_list = ",".join(chunk)

        params = {
            "get": variable_str,
            "for": f"zip code tabulation area:{zip_list}",
        }
        if CENSUS_API_KEY:
            params["key"] = CENSUS_API_KEY

        time.sleep(0.5)  # Be polite to the Census API

        try:
            response = requests.get(CENSUS_BASE, params=params, timeout=30)
            response.raise_for_status()
            data = response.json()

            headers, *records = data
            for record in records:
                all_rows.append(dict(zip(headers, record)))

            log.info(
                "Census chunk %d/%d complete — %d ZIPs fetched",
                (i // chunk_size) + 1,
                (len(clean_zips) + chunk_size - 1) // chunk_size,
                len(chunk),
            )

        except requests.HTTPError as e:
            log.warning("Census HTTP error for chunk starting ZIP %d: %s", i, e)
        except Exception as e:
            log.warning("Census fetch failed for chunk starting %d: %s", i, e)

    if not all_rows:
        log.error("Census enrichment returned zero rows. Check API key and ZIP codes.")
        return pd.DataFrame()

    df = pd.DataFrame(all_rows)

    # Rename raw Census codes to readable names
    rename_map = {**ACS_VARIABLES, "zip code tabulation area": "zip_code"}
    df.rename(columns=rename_map, inplace=True)

    # Convert all numeric columns
    numeric_cols = list(ACS_VARIABLES.values())
    for col in numeric_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")
            # Census uses -666666666 as null sentinel
            df[col] = df[col].where(df[col] >= 0, other=None)

    # ── Derived metrics — these are what the analysis actually uses ──────────

    # Median daily income: the denominator in the Bail Gap calculation
    # If your daily income is $80 and bail is $500, that's 6.25 work-days to freedom.
    # If your daily income is $400, it's 1.25 days.
    # That's the gap. That's what this number makes visible.
    df["median_daily_income"] = (df["median_household_income"] / 365).round(2)

    # Poverty rate
    df["poverty_rate_pct"] = (
        df["people_below_poverty_line"] / df["poverty_universe_total"] * 100
    ).round(2)

    # Single-parent household rate
    df["single_parent_children"] = (
        df["children_single_mother_hh"].fillna(0) + df["children_single_father_hh"].fillna(0)
    )
    df["pct_children_single_parent"] = (
        df["single_parent_children"] / df["children_total"] * 100
    ).round(2)

    # Severe rent burden (paying more than half income on rent — one arrest away from homeless)
    df["pct_severely_rent_burdened"] = (
        df["rent_burdened_50pct_plus"] / df["renter_universe_total"] * 100
    ).round(2)

    # Education (less than bachelor's = may not know legal rights, can't afford private attorney)
    df["pct_bachelors_or_higher"] = (
        df["bachelors_degree_count"] / df["education_universe_total"] * 100
    ).round(2)

    # Racial composition (aggregate percentages — for disparity analysis only)
    df["pct_black"] = (df["black_alone"] / df["total_population"] * 100).round(2)
    df["pct_white"] = (df["white_alone"] / df["total_population"] * 100).round(2)
    df["pct_hispanic"] = (df["hispanic_or_latino"] / df["total_population"] * 100).round(2)

    # Keep only the derived and key columns for the join
    output_cols = [
        "zip_code",
        "total_population",
        "median_household_income",
        "median_daily_income",
        "poverty_rate_pct",
        "pct_children_single_parent",
        "pct_severely_rent_burdened",
        "pct_bachelors_or_higher",
        "pct_black",
        "pct_white",
        "pct_hispanic",
    ]

    result = df[[c for c in output_cols if c in df.columns]].copy()
    log.info(
        "Census enrichment complete. %d ZIPs with data (%.1f%% coverage).",
        result["zip_code"].notna().sum(),
        result["median_household_income"].notna().mean() * 100,
    )
    return result


def enrich_with_census(jail_df: pd.DataFrame, zip_col: str) -> pd.DataFrame:
    """
    Join Census ACS data onto the jail intake DataFrame by ZIP code.

    Args:
        jail_df:  The jail intake DataFrame (already ethics-layer processed)
        zip_col:  Name of the ZIP code column in jail_df

    Returns:
        jail_df with Census columns added via LEFT JOIN on zip_col.
    """
    if zip_col not in jail_df.columns:
        log.warning("ZIP column '%s' not found. Skipping Census enrichment.", zip_col)
        return jail_df

    unique_zips = jail_df[zip_col].dropna().unique().tolist()
    census_df = fetch_acs_for_zips(unique_zips)

    if census_df.empty:
        log.warning("Census enrichment returned empty — jail data unchanged.")
        return jail_df

    enriched = jail_df.merge(
        census_df,
        left_on=zip_col,
        right_on="zip_code",
        how="left",
    )

    coverage = enriched["median_household_income"].notna().mean() * 100
    log.info(
        "Census join complete. Coverage: %.1f%% of intake rows have Census data.",
        coverage,
    )
    if coverage < 50:
        log.warning(
            "Census coverage is below 50%%. "
            "Check that ZIP codes in the jail data match ZCTA boundaries. "
            "Rural/non-standard ZIPs sometimes don't map cleanly."
        )

    return enriched
