"""
ethics.py
---------
Privacy-first transformations. This runs BEFORE anything touches disk.

The people in this data did not consent to being analyzed.
They are not abstractions. Every row is a person.
We handle it accordingly.
"""

import hashlib
import os
import logging
from typing import Optional

import pandas as pd

log = logging.getLogger(__name__)

# Salt stored in environment — never hardcoded, never committed
# Generate once with: python -c "import secrets; print(secrets.token_hex(32))"
SALT = os.environ.get("PII_SALT", "CHANGE_THIS_IN_YOUR_ENV_FILE")


def hash_pii(value: str) -> str:
    """
    One-way SHA-256 hash of any PII field.

    Why SHA-256 with a salt:
    - One-way: you cannot reverse it back to a name or ID
    - Consistent: the same person across multiple bookings hashes identically,
      so you can track patterns over time without ever storing their name
    - Salted: prevents rainbow table attacks if the database is ever exposed

    The same person → the same hash → linkable for analysis.
    No name ever stored.
    """
    if pd.isna(value) or str(value).strip() == "":
        return "UNKNOWN"
    salted = f"{SALT}:{str(value).strip().upper()}"
    return hashlib.sha256(salted.encode("utf-8")).hexdigest()


def age_bucket(age: Optional[float]) -> str:
    """
    Replace exact age with a policy-relevant range.

    Why buckets instead of exact age:
    Age + gender + charge + ZIP + date is enough to re-identify someone
    in a small population. Bucketing removes that risk while keeping
    every analytical insight that matters for policy:
    - Are youth being charged as adults?
    - Are elderly people dying in pretrial detention?
    - Are young adults (18-24) the most affected by cash bail?

    Those questions are all answerable with buckets.
    Exact age adds nothing except re-identification risk.
    """
    if age is None or pd.isna(age):
        return "Unknown"
    try:
        age = int(float(age))
    except (ValueError, TypeError):
        return "Unknown"

    if age < 18:  return "<18"
    if age < 25:  return "18-24"
    if age < 35:  return "25-34"
    if age < 45:  return "35-44"
    if age < 55:  return "45-54"
    if age < 65:  return "55-64"
    return "65+"


# Columns that constitute PII across all source systems
# This list is deliberately broad — when in doubt, hash it
PII_COLUMNS = [
    "inmateid", "inmtid", "inmate_id",
    "name", "first_name", "last_name", "full_name",
    "nysid",                    # NY State ID
    "book_case_id", "booking_number", "arrest_id",
    "defendant_id", "person_id",
    "dob", "date_of_birth",     # DOB is PII even without a name
    "address", "street_address",
    "phone", "phone_number",
    "social_security", "ssn",
]

AGE_COLUMNS = ["age", "age_at_booking", "defendant_age"]


def apply_ethics_layer(df: pd.DataFrame) -> pd.DataFrame:
    """
    Apply all privacy transformations to a raw intake DataFrame.

    Order matters:
    1. Hash PII columns → creates *_hash columns
    2. Drop original PII columns
    3. Bucket age → creates age_bucket column
    4. Drop raw age columns

    Raw PII never survives this function.
    """
    # --- Hash PII ---
    pii_found = [col for col in PII_COLUMNS if col in df.columns]
    for col in pii_found:
        df[f"{col}_hash"] = df[col].astype(str).apply(hash_pii)
        log.info("Hashed PII column: %s → %s_hash", col, col)
    if pii_found:
        df.drop(columns=pii_found, inplace=True)

    # --- Bucket age ---
    age_found = [col for col in AGE_COLUMNS if col in df.columns]
    for col in age_found:
        df["age_bucket"] = pd.to_numeric(df[col], errors="coerce").apply(age_bucket)
        log.info("Age bucketed from column: %s", col)
    if age_found:
        df.drop(columns=age_found, inplace=True)

    # --- Verify no raw PII remains ---
    remaining_pii = [col for col in PII_COLUMNS + AGE_COLUMNS if col in df.columns]
    if remaining_pii:
        # Hard stop — do not allow PII to continue downstream
        raise RuntimeError(
            f"PII columns still present after ethics layer: {remaining_pii}. "
            "Pipeline halted. Check PII_COLUMNS list."
        )

    log.info("Ethics layer complete. Shape after: %s", df.shape)
    return df
