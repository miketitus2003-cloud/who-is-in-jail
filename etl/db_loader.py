"""
db_loader.py
------------
Load the cleaned, enriched Parquet into PostgreSQL.

Reads data/jail_enriched_latest.parquet (output of pipeline.py)
and upserts into the star schema created by sql/schema/ddl.sql.

Run after pipeline.py:
    python etl/db_loader.py
"""

import logging
import os
from pathlib import Path

import pandas as pd
import psycopg2
from psycopg2.extras import execute_values
from dotenv import load_dotenv

load_dotenv()

log = logging.getLogger(__name__)

DATA_DIR = Path("data")
PARQUET_PATH = DATA_DIR / "jail_enriched_latest.parquet"


def get_conn() -> psycopg2.extensions.connection:
    return psycopg2.connect(
        host=os.environ.get("DB_HOST", "localhost"),
        port=int(os.environ.get("DB_PORT", 5432)),
        dbname=os.environ.get("DB_NAME", "jail_data"),
        user=os.environ.get("DB_USER", "postgres"),
        password=os.environ.get("DB_PASSWORD", ""),
    )


def upsert_geography(conn, df: pd.DataFrame) -> dict[str, int]:
    """Insert unique ZIPs into dim_geography. Returns {zip_code: geo_key}."""
    geo_cols = [
        "zip_code", "jurisdiction",
        "median_household_income", "median_daily_income",
        "poverty_rate_pct", "pct_children_single_parent",
        "pct_severely_rent_burdened", "pct_bachelors_or_higher",
        "total_population", "pct_black", "pct_white", "pct_hispanic",
    ]
    zip_col = next((c for c in ["zip_code", "zipcode", "zip", "home_zip"] if c in df.columns), None)
    if not zip_col:
        log.warning("No ZIP column — dim_geography will be empty.")
        return {}

    present_cols = [c for c in geo_cols if c in df.columns]
    geo_df = df[present_cols].drop_duplicates(subset=["zip_code"]).dropna(subset=["zip_code"])

    with conn.cursor() as cur:
        # Build rows in the exact column order so positional VALUES %s matches
        rows = [tuple(row[c] for c in present_cols) for _, row in geo_df.iterrows()]
        sql = f"""
            INSERT INTO dim_geography ({", ".join(present_cols)})
            VALUES %s
            ON CONFLICT (zip_code) DO UPDATE SET
                median_household_income = EXCLUDED.median_household_income,
                median_daily_income     = EXCLUDED.median_daily_income,
                poverty_rate_pct        = EXCLUDED.poverty_rate_pct
            RETURNING zip_code, geo_key
        """
        execute_values(cur, sql, rows)
        mapping = {row[0]: row[1] for row in cur.fetchall()}
    conn.commit()
    log.info("dim_geography: %d ZIPs upserted.", len(mapping))
    return mapping


def upsert_inmates(conn, df: pd.DataFrame) -> dict[str, int]:
    """Insert unique hashed inmates. Returns {inmate_id_hash: inmate_key}."""
    hash_col = next((c for c in df.columns if c.endswith("_hash") and "inmate" in c), None)
    if not hash_col:
        log.warning("No inmate hash column found — dim_inmate will be empty.")
        return {}

    inmate_df = df[[
        hash_col,
        *[c for c in ["age_bucket", "gender", "race_ethnicity", "home_zip_code"] if c in df.columns]
    ]].rename(columns={hash_col: "inmate_id_hash"}).drop_duplicates(subset=["inmate_id_hash"])

    if "age_bucket" not in inmate_df.columns:
        inmate_df["age_bucket"] = "Unknown"
    inmate_df["age_bucket"] = inmate_df["age_bucket"].fillna("Unknown")

    cols = list(inmate_df.columns)
    with conn.cursor() as cur:
        rows = [tuple(row[c] for c in cols) for _, row in inmate_df.iterrows()]
        sql = f"""
            INSERT INTO dim_inmate ({", ".join(cols)})
            VALUES %s
            ON CONFLICT (inmate_id_hash) DO NOTHING
            RETURNING inmate_id_hash, inmate_key
        """
        execute_values(cur, sql, rows)
        mapping = {row[0]: row[1] for row in cur.fetchall()}
    conn.commit()
    log.info("dim_inmate: %d records upserted.", len(mapping))
    return mapping


def upsert_facilities(conn, df: pd.DataFrame) -> dict[str, int]:
    """Insert unique facilities. Returns {facility_id: facility_key}."""
    fac_col = next((c for c in ["facility", "facility_id", "facility_name", "housed_in_facility"]
                    if c in df.columns), None)
    if not fac_col:
        log.warning("No facility column — using default facility per jurisdiction.")
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO dim_facility (facility_id, facility_name, jurisdiction)
                VALUES
                    ('NYC-DEFAULT', 'NYC DOC', 'NYC'),
                    ('LA-DEFAULT',  'LA County Jail', 'LA'),
                    ('DC-DEFAULT',  'DC DOC', 'DC'),
                    ('MD-DEFAULT',  'Maryland Pretrial', 'MD')
                ON CONFLICT (facility_id) DO NOTHING
                RETURNING facility_id, facility_key
            """)
            mapping = {row[0]: row[1] for row in cur.fetchall()}
        conn.commit()
        return mapping

    fac_df = df[[fac_col, "jurisdiction"]].rename(
        columns={fac_col: "facility_name"}
    ).drop_duplicates()
    fac_df["facility_id"] = fac_df["jurisdiction"] + "-" + fac_df["facility_name"].str[:30]

    with conn.cursor() as cur:
        rows = [tuple(r) for r in fac_df[["facility_id", "facility_name", "jurisdiction"]].itertuples(index=False)]
        execute_values(cur, """
            INSERT INTO dim_facility (facility_id, facility_name, jurisdiction)
            VALUES %s
            ON CONFLICT (facility_id) DO NOTHING
            RETURNING facility_id, facility_key
        """, rows)
        mapping = {row[0]: row[1] for row in cur.fetchall()}
    conn.commit()
    log.info("dim_facility: %d facilities upserted.", len(mapping))
    return mapping


def build_charge_map(conn) -> dict[str, int]:
    """
    Return {section_number: charge_key} for all charges in dim_charges.

    Seeds store sections as "PL 220.09". NYC API returns bare "220.09".
    We strip the "PL " prefix so lookups match raw API values.
    We also add prefix keys (e.g. "220" → first matching charge for that PL article)
    so partial section numbers still resolve to something meaningful.
    """
    with conn.cursor() as cur:
        cur.execute("SELECT penal_law_section, charge_key FROM dim_charges WHERE penal_law_section IS NOT NULL;")
        rows = cur.fetchall()

    mapping: dict[str, int] = {}
    for section, key in rows:
        # Exact match: strip "PL " prefix → "220.09"
        bare = section.removeprefix("PL ").strip()
        mapping[bare] = key
        # Prefix match: "220" → first charge for that article (lower key wins)
        prefix = bare.split(".")[0]
        if prefix not in mapping:
            mapping[prefix] = key

    return mapping


def load_fact_detention(
    conn,
    df: pd.DataFrame,
    geo_map: dict,
    inmate_map: dict,
    facility_map: dict,
) -> int:
    """
    Insert rows into fact_detention.
    Maps dimension keys from the lookup dicts produced above.
    Returns count of rows inserted.
    """
    # Resolve surrogate keys
    zip_col  = next((c for c in ["zip_code", "zipcode", "zip", "home_zip"] if c in df.columns), None)
    hash_col = next((c for c in df.columns if c.endswith("_hash") and "inmate" in c), None)
    fac_col  = next((c for c in ["facility", "facility_id", "facility_name", "housed_in_facility"]
                     if c in df.columns), None)

    if zip_col:
        df["home_geo_key"] = df[zip_col].map(geo_map)
    if hash_col:
        df["inmate_key"] = df[hash_col].map(inmate_map)
    if fac_col:
        fac_id_col = df["jurisdiction"] + "-" + df[fac_col].str[:30]
        df["facility_key"] = fac_id_col.map(facility_map)

    # Resolve charge key from raw penal law section (e.g. "PL 220.09")
    charge_map = build_charge_map(conn)
    if "charge_code_raw" in df.columns:
        df["primary_charge_key"] = df["charge_code_raw"].map(charge_map)

    # Use default facility key if specific not found
    for jur, fac_id in [("NYC","NYC-DEFAULT"),("LA","LA-DEFAULT"),("DC","DC-DEFAULT"),("MD","MD-DEFAULT")]:
        default_key = facility_map.get(fac_id)
        if default_key and "facility_key" in df.columns:
            df.loc[df["jurisdiction"] == jur, "facility_key"] = df.loc[
                df["jurisdiction"] == jur, "facility_key"
            ].fillna(default_key)

    fact_cols = {
        "inmate_key":           "inmate_key",
        "facility_key":         "facility_key",
        "home_geo_key":         "home_geo_key",
        "primary_charge_key":   "primary_charge_key" if "primary_charge_key" in df.columns else None,
        "jurisdiction":         "jurisdiction",
        "booking_date":         next((c for c in ["booking_date","admitted_dt","book_date"] if c in df.columns), None),
        "release_date":         next((c for c in ["release_date","discharge_date"] if c in df.columns), None),
        "bail_set_amount":      next((c for c in ["bail_set_amount","bail_amount","bond_amount"] if c in df.columns), None),
        "bail_type":            next((c for c in ["bail_type","bond_type"] if c in df.columns), None),
        "work_days_to_bail":    "work_days_to_bail" if "work_days_to_bail" in df.columns else None,
        "is_md_reform_case":    "is_md_reform_case" if "is_md_reform_case" in df.columns else None,
        "source_system":        "source_system",
        "etl_batch_id":         "etl_batch_id",
    }

    insert_cols = {k: v for k, v in fact_cols.items() if v and v in df.columns}
    out_df = df[[v for v in insert_cols.values()]].rename(
        columns={v: k for k, v in insert_cols.items()}
    )
    out_df = out_df.dropna(subset=["inmate_key", "facility_key", "jurisdiction"])

    cols = list(out_df.columns)
    with conn.cursor() as cur:
        rows = [tuple(row[c] for c in cols) for _, row in out_df.iterrows()]
        execute_values(
            cur,
            f"INSERT INTO fact_detention ({', '.join(cols)}) VALUES %s",
            rows,
            page_size=500,
        )
    conn.commit()
    log.info("fact_detention: %d rows inserted.", len(out_df))
    return len(out_df)


def refresh_materialized_views(conn) -> None:
    """
    Refresh materialized views.
    Uses CONCURRENTLY so reads are not blocked — but CONCURRENTLY fails if the
    view is empty (first run). We detect that and fall back to a plain REFRESH.
    """
    with conn.cursor() as cur:
        for view in ("mv_bail_gap_by_zip", "mv_innocence_by_jurisdiction"):
            cur.execute(f"SELECT COUNT(*) FROM {view};")
            row_count = cur.fetchone()[0]
            if row_count > 0:
                cur.execute(f"REFRESH MATERIALIZED VIEW CONCURRENTLY {view};")
                log.info("Refreshed %s concurrently (%d existing rows).", view, row_count)
            else:
                cur.execute(f"REFRESH MATERIALIZED VIEW {view};")
                log.info("Refreshed %s (initial population).", view)
    conn.commit()


def run_loader(parquet_path: Path = PARQUET_PATH) -> None:
    if not parquet_path.exists():
        raise FileNotFoundError(
            f"{parquet_path} not found. Run `python etl/pipeline.py` first."
        )

    log.info("Loading %s into PostgreSQL...", parquet_path)
    df = pd.read_parquet(parquet_path)
    log.info("Parquet loaded: %d rows, %d columns.", len(df), len(df.columns))

    conn = get_conn()
    try:
        geo_map      = upsert_geography(conn, df)
        inmate_map   = upsert_inmates(conn, df)
        facility_map = upsert_facilities(conn, df)
        count        = load_fact_detention(conn, df, geo_map, inmate_map, facility_map)
        refresh_materialized_views(conn)
        log.info("Load complete. %d fact rows in database.", count)
    finally:
        conn.close()


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
    )
    run_loader()
