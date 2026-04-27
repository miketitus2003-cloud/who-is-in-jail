"""
pipeline.py
-----------
Master ETL orchestrator.

Order of operations — non-negotiable:
  1. Extract raw data from source APIs
  2. Apply column maps (raw API names → schema names)
  3. Apply ethics layer (hash PII, bucket ages) BEFORE anything touches disk
  4. Derive pretrial status from status codes (NYC-specific)
  5. Enrich with US Census ACS socioeconomic data
  6. Compute bail gap and MD reform tags
  7. Write clean, anonymized Parquet to data/

Run:
    python etl/pipeline.py               # full load
    python etl/pipeline.py --since-days 30  # incremental
"""

import logging
import os
import sys
import uuid
from datetime import datetime
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv

load_dotenv()

# DATA_DIR must exist before FileHandler tries to open a log file inside it
DATA_DIR = Path("data")
DATA_DIR.mkdir(exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(DATA_DIR / f"pipeline_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.log"),
    ],
)
log = logging.getLogger("pipeline")

from etl.sources import SOCRATA_SOURCES
from etl.extract import extract_all_sources
from etl.ethics import apply_ethics_layer
from etl.census import enrich_with_census

ZIP_COLUMN_CANDIDATES = [
    "zip_code", "zipcode", "zip", "home_zip",
    "booking_zip", "residence_zip", "addr_zip",
]

# NYC inmate_status_code → pretrial flag
# Confirmed from live API: DE = Detained (pretrial), CS = Sentenced, etc.
NYC_PRETRIAL_STATUS_CODES = {"DE", "DEP", "DNS"}   # detained, not sentenced
NYC_SENTENCED_STATUS_CODES = {"CS", "CSP", "SSR"}  # convicted, serving time
NYC_PAROLE_CODES = {"DPV"}                          # parole/probation violation


def apply_column_map(df: pd.DataFrame, source_name: str) -> pd.DataFrame:
    """
    Rename raw API columns to our schema names using each source's column_map.
    Sources without column_maps (LA, MD placeholders) are passed through unchanged.
    """
    source = next((s for s in SOCRATA_SOURCES if s.name == source_name), None)
    if source and source.column_map:
        rename = {k: v for k, v in source.column_map.items() if k in df.columns}
        df = df.rename(columns=rename)
        log.info("[%s] Applied column map: %d renames.", source_name, len(rename))
    return df


def normalize_all_columns(df: pd.DataFrame) -> pd.DataFrame:
    """
    Apply column maps for each source, then standardize types.
    Called once on the combined DataFrame, operates per jurisdiction.
    """
    if "source_system" not in df.columns:
        return df

    parts = []
    for source_name, group in df.groupby("source_system"):
        parts.append(apply_column_map(group.copy(), source_name))
    return pd.concat(parts, ignore_index=True)


def derive_nyc_pretrial_flag(df: pd.DataFrame) -> pd.DataFrame:
    """
    NYC does not publish bail_set_amount in its open data.
    We derive pretrial status from inmate_status_code:
      DE / DEP / DNS = detained pretrial (legally innocent, awaiting trial)
      CS / CSP / SSR = post-conviction (sentenced)
      DPV            = detained on parole/probation violation

    This is an approximation — the most accurate bail data requires
    NYC Criminal Court records (see docs/SOURCES.md).
    """
    nyc_mask = df["jurisdiction"] == "NYC"
    if not nyc_mask.any() or "detention_status_code" not in df.columns:
        return df

    df["pretrial_derived"] = False
    df.loc[nyc_mask, "pretrial_derived"] = (
        df.loc[nyc_mask, "detention_status_code"]
          .str.strip()
          .isin(NYC_PRETRIAL_STATUS_CODES)
    )

    pretrial_count = df.loc[nyc_mask, "pretrial_derived"].sum()
    total_nyc = nyc_mask.sum()
    log.info(
        "NYC pretrial derivation: %d / %d (%.1f%%) flagged as pretrial from status code.",
        pretrial_count, total_nyc,
        100.0 * pretrial_count / total_nyc if total_nyc else 0,
    )
    return df


def find_zip_column(df: pd.DataFrame) -> str | None:
    for candidate in ZIP_COLUMN_CANDIDATES:
        if candidate in df.columns:
            return candidate
    return None


def compute_bail_gap(df: pd.DataFrame) -> pd.DataFrame:
    """
    Work-days-to-bail = bail_set_amount / median_daily_income.

    Where bail amount is missing (NYC open data doesn't publish it),
    this metric is NULL — flagged in the log so the gap is transparent,
    not silently hidden.
    """
    if "bail_set_amount" in df.columns and "median_daily_income" in df.columns:
        df["bail_set_amount_num"] = pd.to_numeric(df["bail_set_amount"], errors="coerce")
        df["work_days_to_bail"] = (
            df["bail_set_amount_num"] / df["median_daily_income"]
        ).round(1)
        coverage = df["work_days_to_bail"].notna().mean() * 100
        log.info(
            "Bail gap computed. Coverage: %.1f%% of rows. Median: %.1f days.",
            coverage,
            df["work_days_to_bail"].median() if df["work_days_to_bail"].notna().any() else 0,
        )
        if coverage < 30:
            log.warning(
                "Bail gap coverage is %.1f%%. "
                "This is expected if using NYC open data (no bail amount field). "
                "To improve: add court records data per docs/SOURCES.md.",
                coverage,
            )
    else:
        log.warning("Cannot compute bail gap — bail_set_amount or median_daily_income missing.")
    return df


def tag_md_reform(df: pd.DataFrame) -> pd.DataFrame:
    """
    Flag Maryland records pre/post July 1, 2017 bail reform.
    With aggregate Vera data this operates on annual records.
    With individual booking records (via MPIA) this works row-by-row.
    """
    if "booking_date" not in df.columns or "jurisdiction" not in df.columns:
        return df

    df["booking_date_parsed"] = pd.to_datetime(df["booking_date"], errors="coerce")
    reform_date = pd.Timestamp("2017-07-01")
    md_mask = df["jurisdiction"] == "MD"
    df["is_md_reform_case"] = False
    df.loc[md_mask, "is_md_reform_case"] = (
        df.loc[md_mask, "booking_date_parsed"] >= reform_date
    )

    pre  = (md_mask & (df["booking_date_parsed"] < reform_date)).sum()
    post = (md_mask & df["is_md_reform_case"]).sum()
    log.info("MD reform tagging: %d pre-reform, %d post-reform.", pre, post)
    return df


def run_pipeline(since_days: int | None = None) -> pd.DataFrame:
    """
    Full pipeline: Extract → Normalize → Ethics → Census → Metrics → Save.
    """
    batch_id = str(uuid.uuid4())
    log.info("=" * 70)
    log.info("WHO IS IN JAIL — AND WHY?")
    log.info("Pipeline start. Batch ID: %s", batch_id)
    log.info("=" * 70)

    # ── Step 1: Extract ───────────────────────────────────────────────────────
    # Skips sources where dataset_id == "NEEDS_VERIFICATION"
    active_sources = [s for s in SOCRATA_SOURCES if s.dataset_id != "NEEDS_VERIFICATION"]
    log.info("STEP 1: Extracting from %d verified sources...", len(active_sources))
    raw_df = extract_all_sources(active_sources, since_days=since_days)
    log.info("Raw extraction complete. Shape: %s", raw_df.shape)

    # ── Step 2: Column normalization ──────────────────────────────────────────
    log.info("STEP 2: Applying column maps (raw API names → schema names).")
    normalized_df = normalize_all_columns(raw_df)

    # ── Step 3: Ethics Layer ──────────────────────────────────────────────────
    log.info("STEP 3: Applying ethics layer. PII will not survive this step.")
    clean_df = apply_ethics_layer(normalized_df)
    log.info("Ethics layer complete. Shape: %s", clean_df.shape)

    # ── Step 4: Jurisdiction-specific derivations ─────────────────────────────
    log.info("STEP 4: Deriving pretrial flags from status codes.")
    clean_df = derive_nyc_pretrial_flag(clean_df)

    # ── Step 5: Census Enrichment ─────────────────────────────────────────────
    log.info("STEP 5: Enriching with Census ACS socioeconomic data.")
    zip_col = find_zip_column(clean_df)
    if zip_col:
        enriched_df = enrich_with_census(clean_df, zip_col)
    else:
        log.warning(
            "No ZIP column in data — Census enrichment skipped. "
            "NYC open data does not include home ZIP. "
            "ZIP data available via court records (see docs/SOURCES.md)."
        )
        enriched_df = clean_df

    # ── Step 6: Derived Metrics ───────────────────────────────────────────────
    log.info("STEP 6: Computing bail gap and reform tags.")
    enriched_df = compute_bail_gap(enriched_df)
    enriched_df = tag_md_reform(enriched_df)
    enriched_df["etl_batch_id"] = batch_id
    enriched_df["etl_loaded_at"] = datetime.utcnow().isoformat()

    # ── Step 7: Save ──────────────────────────────────────────────────────────
    timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    output_path = DATA_DIR / f"jail_enriched_{timestamp}.parquet"
    latest_path = DATA_DIR / "jail_enriched_latest.parquet"

    enriched_df.to_parquet(output_path, index=False)
    enriched_df.to_parquet(latest_path, index=False)

    log.info("=" * 70)
    log.info("PIPELINE COMPLETE")
    log.info("Rows: %d | Columns: %d", len(enriched_df), len(enriched_df.columns))
    log.info("Saved: %s", output_path)
    log.info("Jurisdictions: %s", enriched_df["jurisdiction"].value_counts().to_dict())
    if "pretrial_derived" in enriched_df.columns:
        nyc_pretrial = enriched_df.loc[
            enriched_df["jurisdiction"] == "NYC", "pretrial_derived"
        ].mean() * 100
        log.info("NYC: %.1f%% flagged as pretrial (from status code).", nyc_pretrial)
    log.info("=" * 70)

    return enriched_df


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Who Is in Jail — ETL Pipeline")
    parser.add_argument(
        "--since-days", type=int, default=None,
        help="Only pull records from the last N days (omit for full load)",
    )
    args = parser.parse_args()
    df = run_pipeline(since_days=args.since_days)
    print(f"\nDone. {len(df):,} rows ready for analysis.")
    print(f"Output: data/jail_enriched_latest.parquet")
