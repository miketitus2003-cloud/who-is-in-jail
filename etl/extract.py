"""
extract.py
----------
Paginated extractors for all source types.

NYC / LA / MD: Socrata API  → extract_socrata()
DC:            ArcGIS REST  → extract_dc()

Both normalize to the same DataFrame schema before returning.
"""

import time
import logging
from datetime import datetime, timedelta

import requests
import pandas as pd
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from etl.sources import SocrataSource, DCSource, DC_SOURCE

log = logging.getLogger(__name__)


def build_session(retries: int = 6, backoff: float = 2.0) -> requests.Session:
    """
    Session with exponential backoff on server errors and rate limits.

    If the server says "slow down" (429) or falls over (500/502/503/504),
    we wait and try again. We are polite guests in other people's APIs.
    """
    session = requests.Session()
    retry = Retry(
        total=retries,
        backoff_factor=backoff,           # waits: 2s, 4s, 8s, 16s, 32s, 64s
        status_forcelist=[429, 500, 502, 503, 504],
        respect_retry_after_header=True,  # honor the server's own timing
        allowed_methods=["GET"],
    )
    adapter = HTTPAdapter(max_retries=retry)
    session.mount("https://", adapter)
    session.mount("http://", adapter)
    return session


SESSION = build_session()


def extract_socrata(
    source: SocrataSource,
    since_date: datetime | None = None,
    polite_delay: float = 0.4,
) -> pd.DataFrame:
    """
    Pull all records from a Socrata endpoint, handling pagination automatically.

    Args:
        source:        SocrataSource config object
        since_date:    Only pull records after this date (for incremental loads)
        polite_delay:  Seconds to wait between requests — don't hammer the API

    Returns:
        DataFrame of all records from this source, with jurisdiction tagged.
    """
    all_rows = []
    page = 0

    # Warn once about missing token — not on every page request
    if not source.app_token:
        log.warning(
            "[%s] No app token found for env var %s. "
            "Rate limits will be strict (1,000 rows/request). "
            "Get a free token at the data portal.",
            source.name, source.token_env_var,
        )

    # Build date filter for incremental loads
    where_clause = None
    if since_date:
        since_str = since_date.strftime("%Y-%m-%dT%H:%M:%S")
        where_clause = f"{source.date_field} >= '{since_str}'"
        log.info("[%s] Incremental load — pulling since %s", source.name, since_str)
    else:
        log.info("[%s] Full load — pulling all records", source.name)

    while True:
        params = {
            "$limit": source.limit,
            "$offset": page * source.limit,
            "$order": f"{source.date_field} ASC",
            **source.extra_params,
        }

        if source.app_token:
            params["$$app_token"] = source.app_token

        if where_clause:
            params["$where"] = where_clause

        log.info(
            "[%s] Page %d — offset %d",
            source.name, page, params["$offset"]
        )

        time.sleep(polite_delay)

        try:
            response = SESSION.get(source.endpoint, params=params, timeout=45)
            response.raise_for_status()
            rows = response.json()
        except requests.HTTPError as e:
            log.error("[%s] HTTP error on page %d: %s", source.name, page, e)
            log.error("URL attempted: %s", response.url if 'response' in dir() else "unknown")
            break
        except requests.ConnectionError as e:
            log.error("[%s] Connection error: %s", source.name, e)
            break
        except Exception as e:
            log.error("[%s] Unexpected error: %s", source.name, e)
            break

        if not rows:
            log.info("[%s] No more rows — extraction complete.", source.name)
            break

        all_rows.extend(rows)
        log.info("[%s] %d total rows fetched so far.", source.name, len(all_rows))

        if len(rows) < source.limit:
            # Last page — fewer rows than the page size means we're done
            break

        page += 1

    if not all_rows:
        log.warning("[%s] Zero rows returned. Check dataset ID and token.", source.name)
        return pd.DataFrame()

    df = pd.DataFrame(all_rows)
    df["jurisdiction"] = source.jurisdiction
    df["source_system"] = source.name
    df["extracted_at"] = datetime.utcnow().isoformat()

    # Normalize column names: lowercase, underscores
    df.columns = [c.lower().strip().replace(" ", "_").replace("-", "_") for c in df.columns]

    log.info(
        "[%s] Extraction complete. %d rows, %d columns.",
        source.name, len(df), len(df.columns)
    )
    return df


def extract_dc(
    source: DCSource,
    since_date: datetime | None = None,
    polite_delay: float = 0.5,
) -> pd.DataFrame:
    """
    DC Open Data uses ArcGIS REST API — different format from Socrata.
    Paginates via resultOffset / resultRecordCount.
    Returns normalized DataFrame matching Socrata output schema.
    """
    all_rows = []
    offset = 0
    log.info("[%s] Starting ArcGIS extraction...", source.name)

    while True:
        params = {**source.base_params, "resultOffset": offset}

        if since_date:
            since_str = since_date.strftime("%Y-%m-%d %H:%M:%S")
            params["where"] = f"{source.date_field} >= DATE '{since_str}'"

        time.sleep(polite_delay)
        try:
            response = SESSION.get(source.endpoint, params=params, timeout=45)
            response.raise_for_status()
            data = response.json()
        except Exception as e:
            log.error("[%s] Error at offset %d: %s", source.name, offset, e)
            break

        # ArcGIS returns {"features": [{"attributes": {...}}, ...]}
        features = data.get("features", [])
        if not features:
            break

        rows = [f["attributes"] for f in features]
        all_rows.extend(rows)
        log.info("[%s] %d rows fetched so far.", source.name, len(all_rows))

        if len(rows) < source.page_size:
            break
        offset += source.page_size

    if not all_rows:
        log.warning("[%s] Zero rows returned.", source.name)
        return pd.DataFrame()

    df = pd.DataFrame(all_rows)
    df.columns = [c.lower().strip().replace(" ", "_") for c in df.columns]
    df["jurisdiction"] = source.jurisdiction
    df["source_system"] = source.name
    df["extracted_at"] = datetime.utcnow().isoformat()

    log.info("[%s] Complete. %d rows, %d columns.", source.name, len(df), len(df.columns))
    return df


def extract_all_sources(
    sources: list[SocrataSource],
    since_days: int | None = None,
) -> pd.DataFrame:
    """
    Extract from every source (Socrata + DC ArcGIS) and return a combined DataFrame.
    """
    since_date = None
    if since_days:
        since_date = datetime.utcnow() - timedelta(days=since_days)

    all_dfs = []
    failed_sources = []

    # Socrata sources (NYC, LA, MD)
    for source in sources:
        log.info("=" * 60)
        log.info("Starting: %s", source.name)
        log.info("=" * 60)
        try:
            df = extract_socrata(source, since_date=since_date)
            if not df.empty:
                all_dfs.append(df)
        except Exception as e:
            log.error("Source %s failed: %s", source.name, e)
            failed_sources.append(source.name)

    # DC — ArcGIS
    log.info("=" * 60)
    log.info("Starting: %s", DC_SOURCE.name)
    log.info("=" * 60)
    try:
        dc_df = extract_dc(DC_SOURCE, since_date=since_date)
        if not dc_df.empty:
            all_dfs.append(dc_df)
    except Exception as e:
        log.error("DC source failed: %s", e)
        failed_sources.append(DC_SOURCE.name)

    if failed_sources:
        log.warning("Failed sources: %s", failed_sources)
        log.warning("Continuing with successful sources.")

    if not all_dfs:
        raise RuntimeError(
            "All sources failed. Check your API tokens in .env and verify dataset IDs."
        )

    combined = pd.concat(all_dfs, ignore_index=True)
    log.info("All sources combined: %d total rows", len(combined))
    return combined
