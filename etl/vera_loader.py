"""
vera_loader.py
--------------
Load Vera Institute incarceration trends data.

The Vera county CSV is the backbone of the historical analysis —
it goes back to 1970 and covers every county in the country.
It answers questions the individual booking APIs can't:
  - How did we get here? (the long arc of mass incarceration)
  - How does racial disparity look across decades?
  - How do NYC, LA, Baltimore compare to national trends?
  - Did Maryland's 2017 reform show up in the aggregate numbers?

Download first:
    python etl/vera_loader.py --download

Then load into PostgreSQL:
    python etl/vera_loader.py --load
"""

import argparse
import logging
import os
from pathlib import Path

import pandas as pd
import requests

log = logging.getLogger(__name__)

VERA_COUNTY_URL = (
    "https://raw.githubusercontent.com/vera-institute/"
    "incarceration-trends/master/incarceration_trends_county.csv"
)
VERA_STATE_URL = (
    "https://raw.githubusercontent.com/vera-institute/"
    "incarceration-trends/master/incarceration_trends_state.csv"
)

RAW_DIR = Path("data/raw")
COUNTY_PATH = RAW_DIR / "vera_county.csv"
STATE_PATH  = RAW_DIR / "vera_state.csv"

# Counties of interest — FIPS codes for our jurisdictions
TARGET_FIPS = {
    "36005": "Bronx, NY",
    "36047": "Brooklyn, NY",
    "36061": "Manhattan, NY",
    "36081": "Queens, NY",
    "36085": "Staten Island, NY",
    "06037": "Los Angeles, CA",
    "11001": "Washington, DC",
    "24510": "Baltimore City, MD",
    "24033": "Prince George's County, MD",
}


def download_vera() -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    for url, path, label in [
        (VERA_COUNTY_URL, COUNTY_PATH, "County"),
        (VERA_STATE_URL,  STATE_PATH,  "State"),
    ]:
        log.info("Downloading Vera %s data...", label)
        resp = requests.get(url, timeout=60)
        resp.raise_for_status()
        path.write_bytes(resp.content)
        lines = resp.text.count("\n")
        log.info("Saved %s — %d rows.", path, lines)


def load_vera_county(filter_jurisdictions: bool = True) -> pd.DataFrame:
    """
    Load Vera county CSV.
    If filter_jurisdictions=True, return only our four jurisdictions.
    If False, return full national dataset.
    """
    if not COUNTY_PATH.exists():
        raise FileNotFoundError(
            f"{COUNTY_PATH} not found. Run: python etl/vera_loader.py --download"
        )

    df = pd.read_csv(COUNTY_PATH, dtype={"county_fips": str})
    df["county_fips"] = df["county_fips"].str.zfill(5)
    log.info("Vera county loaded: %d rows, %d counties, years %d–%d.",
             len(df), df["county_fips"].nunique(),
             df["year"].min(), df["year"].max())

    if filter_jurisdictions:
        df = df[df["county_fips"].isin(TARGET_FIPS)].copy()
        df["jurisdiction_label"] = df["county_fips"].map(TARGET_FIPS)
        log.info("Filtered to target jurisdictions: %d rows.", len(df))

    return df


def load_vera_state() -> pd.DataFrame:
    if not STATE_PATH.exists():
        raise FileNotFoundError(
            f"{STATE_PATH} not found. Run: python etl/vera_loader.py --download"
        )
    df = pd.read_csv(STATE_PATH)
    log.info("Vera state loaded: %d rows.", len(df))
    return df


def summarize_vera(df: pd.DataFrame) -> None:
    """
    Print key findings from the Vera data for our jurisdictions.
    This is the 'long arc' story — how we got here.
    """
    print("\n" + "=" * 60)
    print("VERA INSTITUTE — INCARCERATION TRENDS")
    print("Key jurisdictions: NYC, LA, DC, Baltimore/PG County MD")
    print("=" * 60)

    latest_year = df["year"].max()
    latest = df[df["year"] == latest_year]

    for fips, label in TARGET_FIPS.items():
        row = latest[latest["county_fips"] == fips]
        if row.empty:
            continue
        row = row.iloc[0]
        pretrial = row.get("total_pretrial_custody", "N/A")
        total    = row.get("total_jail_pop", "N/A")
        black    = row.get("black_jail_pop", "N/A")
        capacity = row.get("jail_rated_capacity", "N/A")

        pretrial_pct = (
            round(100.0 * pretrial / total, 1)
            if pd.notna(pretrial) and pd.notna(total) and total > 0
            else "N/A"
        )
        cap_pct = (
            round(100.0 * total / capacity, 1)
            if pd.notna(capacity) and capacity > 0
            else "N/A"
        )

        print(f"\n{label} ({latest_year}):")
        print(f"  Total jail population:  {int(total) if pd.notna(total) else 'N/A'}")
        print(f"  Pretrial (innocent):    {int(pretrial) if pd.notna(pretrial) else 'N/A'} ({pretrial_pct}%)")
        print(f"  Black jail population:  {int(black) if pd.notna(black) else 'N/A'}")
        print(f"  Capacity utilization:   {cap_pct}%")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

    parser = argparse.ArgumentParser(description="Vera Institute data loader")
    parser.add_argument("--download", action="store_true", help="Download Vera CSVs")
    parser.add_argument("--load",     action="store_true", help="Load and summarize")
    parser.add_argument("--all",      action="store_true", help="All counties, not just target jurisdictions")
    args = parser.parse_args()

    if args.download:
        download_vera()

    if args.load or (not args.download):
        df = load_vera_county(filter_jurisdictions=not args.all)
        summarize_vera(df)
        out = Path("data/vera_jurisdictions.parquet")
        df.to_parquet(out, index=False)
        print(f"\nSaved to {out}")
