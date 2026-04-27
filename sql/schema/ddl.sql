-- ============================================================
-- WHO IS IN JAIL — AND WHY?
-- PostgreSQL Star Schema
-- ============================================================
-- Every table here is designed around a question, not a data model.
-- The questions:
--   Who is in here? (dim_inmate — anonymized)
--   Where are they from? (dim_geography — Census enriched)
--   What are they charged with? (dim_charges — classified by type)
--   Where are they being held? (dim_facility — with conditions data)
--   What happened to them? (fact_detention — the center of everything)
-- ============================================================

-- Clean start — safe to run repeatedly in development
DROP TABLE IF EXISTS fact_detention        CASCADE;
DROP TABLE IF EXISTS dim_inmate            CASCADE;
DROP TABLE IF EXISTS dim_geography         CASCADE;
DROP TABLE IF EXISTS dim_facility          CASCADE;
DROP TABLE IF EXISTS dim_charges           CASCADE;
DROP TABLE IF EXISTS stg_deaths_in_custody CASCADE;
DROP MATERIALIZED VIEW IF EXISTS mv_bail_gap_by_zip;
DROP MATERIALIZED VIEW IF EXISTS mv_innocence_by_jurisdiction;

-- ── Dimension: Geography ──────────────────────────────────────────────────────
-- One row per ZIP code, enriched with Census ACS data.
-- This is what makes the bail gap visible:
-- $500 bail in a $35k/year ZIP = 5 days of work.
-- $500 bail in a $150k/year ZIP = half a day.
-- Same bail. Completely different impact.

CREATE TABLE dim_geography (
    geo_key                     SERIAL PRIMARY KEY,
    zip_code                    CHAR(5)         NOT NULL UNIQUE,
    city                        VARCHAR(100),
    county                      VARCHAR(100),
    state                       CHAR(2),
    jurisdiction                VARCHAR(20)     NOT NULL,   -- NYC, LA, DC, MD

    -- Census ACS 5-Year Estimates (2022)
    median_household_income     NUMERIC(12,2),
    median_daily_income         NUMERIC(10,4),              -- income / 365
    poverty_rate_pct            NUMERIC(5,2),
    pct_children_single_parent  NUMERIC(5,2),
    pct_severely_rent_burdened  NUMERIC(5,2),               -- paying >50% income on rent
    pct_bachelors_or_higher     NUMERIC(5,2),
    total_population            INTEGER,

    -- Racial composition (aggregate only — disparity analysis)
    pct_black                   NUMERIC(5,2),
    pct_white                   NUMERIC(5,2),
    pct_hispanic                NUMERIC(5,2),

    -- Eviction Lab data (joined separately)
    eviction_rate_per_100       NUMERIC(6,2),
    eviction_filing_rate        NUMERIC(6,2),

    census_vintage              SMALLINT DEFAULT 2022,

    CONSTRAINT valid_zip CHECK (zip_code ~ '^\d{5}$')
);

COMMENT ON TABLE dim_geography IS
'ZIP-level socioeconomic context. The income data here is what makes bail amounts real.';

COMMENT ON COLUMN dim_geography.median_daily_income IS
'Median household income divided by 365. The denominator in work_days_to_bail.';

COMMENT ON COLUMN dim_geography.pct_severely_rent_burdened IS
'Percent of renters paying >50% of income on rent. One arrest away from homelessness.';


-- ── Dimension: Facility ───────────────────────────────────────────────────────
-- Where people are being held. Includes conditions data.
-- Rikers, LA County, DC Jail, Baltimore City — these are not abstractions.

CREATE TABLE dim_facility (
    facility_key                SERIAL PRIMARY KEY,
    facility_id                 VARCHAR(50)     NOT NULL UNIQUE,
    facility_name               VARCHAR(200)    NOT NULL,
    jurisdiction                VARCHAR(20)     NOT NULL,
    facility_type               VARCHAR(50),                -- Pretrial, Sentenced, Mixed
    security_level              VARCHAR(30),                -- Max, Medium, Min
    rated_capacity              INTEGER,
    geo_key                     INTEGER REFERENCES dim_geography(geo_key),

    -- Conditions data (from NYC BOC, BJS, Marshall Project)
    deaths_in_custody_ytd       INTEGER,
    use_of_force_incidents_ytd  INTEGER,
    solitary_population         INTEGER,
    federal_oversight           BOOLEAN DEFAULT FALSE,      -- under court/DOJ oversight
    oversight_reason            TEXT,
    conditions_last_updated     DATE
);

COMMENT ON TABLE dim_facility IS
'Jail facilities with capacity and conditions data. Rikers is under federal oversight.';


-- ── Dimension: Inmate (Fully Anonymized) ──────────────────────────────────────
-- No names. No DOB. No raw IDs.
-- SHA-256 hash enables longitudinal analysis without storing identity.
-- Age bucket prevents re-identification while keeping policy signal.

CREATE TABLE dim_inmate (
    inmate_key                  SERIAL PRIMARY KEY,
    inmate_id_hash              CHAR(64)        NOT NULL UNIQUE,   -- SHA-256 hex
    age_bucket                  VARCHAR(10)     NOT NULL,
    gender                      VARCHAR(20),
    race_ethnicity              VARCHAR(50),
    home_zip_code               CHAR(5),

    CONSTRAINT valid_age_bucket CHECK (
        age_bucket IN ('<18','18-24','25-34','35-44','45-54','55-64','65+','Unknown')
    )
);

COMMENT ON TABLE dim_inmate IS
'Anonymized individual dimension. SHA-256 hash of original ID. No name or DOB stored.';

COMMENT ON COLUMN dim_inmate.inmate_id_hash IS
'SHA-256(salt + original_id). Enables cross-booking linkage without storing PII.';


-- ── Dimension: Charges ────────────────────────────────────────────────────────
-- This is where the classification work lives.
-- Violent vs. Poverty-linked vs. Addiction vs. Property.
-- The taxonomy (in seeds/charge_taxonomy.sql) is the argument.

CREATE TABLE dim_charges (
    charge_key                  SERIAL PRIMARY KEY,
    charge_code                 VARCHAR(50),
    charge_description          VARCHAR(500)    NOT NULL,
    charge_class                VARCHAR(20),               -- Felony A/B/C/D/E, Misd A/B, Infraction
    charge_category             VARCHAR(50)     NOT NULL,  -- Violent, Property, Drug, Poverty-Linked, Other
    is_violent                  BOOLEAN         NOT NULL DEFAULT FALSE,
    is_poverty_linked           BOOLEAN         NOT NULL DEFAULT FALSE,
    is_addiction_related        BOOLEAN         NOT NULL DEFAULT FALSE,
    -- Poverty-linked examples: fare evasion, trespass, loitering, petit larceny < $250
    -- Addiction-related: possession, paraphernalia, public intoxication
    jurisdiction                VARCHAR(20),               -- some charges are jurisdiction-specific
    penal_law_section           VARCHAR(20),
    ucr_offense_code            VARCHAR(10)
);

COMMENT ON TABLE dim_charges IS
'Charge taxonomy with policy-relevant flags. is_poverty_linked and is_addiction_related
are the basis for the most important queries in this project.';

COMMENT ON COLUMN dim_charges.is_poverty_linked IS
'True for charges that criminalize poverty: fare evasion, trespass, loitering,
petit larceny under $250, panhandling, sleeping in public.';

COMMENT ON COLUMN dim_charges.is_addiction_related IS
'True for charges that reflect addiction rather than predatory behavior:
possession of any controlled substance, paraphernalia, public intoxication.
These belong in treatment, not cages.';


-- ── Fact: Detention Events ────────────────────────────────────────────────────
-- One row per detention event.
-- This is the story of what happened to a person.

CREATE TABLE fact_detention (
    detention_key               BIGSERIAL PRIMARY KEY,

    -- Dimension keys
    inmate_key                  INTEGER         NOT NULL REFERENCES dim_inmate(inmate_key),
    facility_key                INTEGER         NOT NULL REFERENCES dim_facility(facility_key),
    home_geo_key                INTEGER         REFERENCES dim_geography(geo_key),
    primary_charge_key          INTEGER         REFERENCES dim_charges(charge_key),

    -- Core booking facts
    jurisdiction                VARCHAR(20)     NOT NULL,
    booking_date                DATE            NOT NULL,
    release_date                DATE,

    -- Computed: how long were they in there?
    detention_length_days       INTEGER GENERATED ALWAYS AS (
        CASE WHEN release_date IS NOT NULL
        THEN (release_date - booking_date)
        ELSE NULL END
    ) STORED,

    -- Bail facts — the core of the inequity
    bail_set_amount             NUMERIC(12,2),
    bail_type                   VARCHAR(50),
    -- bail_type values: 'Cash', 'Bond', 'ROR', 'Remand', 'No Bail Set',
    --                   'No Bail (MD Reform)', 'Supervised Release'
    bail_paid                   BOOLEAN,

    -- Pretrial: held without conviction
    pretrial_detention_flag     BOOLEAN GENERATED ALWAYS AS (
        bail_set_amount IS NOT NULL AND (bail_paid = FALSE OR bail_paid IS NULL)
    ) STORED,

    -- The bail gap: how many days of work to buy freedom?
    -- Populated by ETL from bail_set_amount / dim_geography.median_daily_income
    work_days_to_bail           NUMERIC(10,2),

    -- MD Reform flag
    is_md_reform_case           BOOLEAN DEFAULT FALSE,
    -- TRUE when jurisdiction='MD' AND booking_date >= '2017-07-01'

    -- Case outcome (if known)
    case_disposition            VARCHAR(50),
    -- values: 'Guilty Plea', 'Trial - Guilty', 'Trial - Not Guilty',
    --         'Dismissed', 'Nolle Prosequi', 'ACD', 'Unknown'
    sentence_type               VARCHAR(50),

    -- Source tracking
    source_system               VARCHAR(100),
    etl_batch_id                UUID,
    etl_loaded_at               TIMESTAMPTZ     DEFAULT NOW(),

    -- Constraints
    CONSTRAINT booking_before_release
        CHECK (release_date IS NULL OR release_date >= booking_date),
    CONSTRAINT positive_bail
        CHECK (bail_set_amount IS NULL OR bail_set_amount >= 0),
    CONSTRAINT valid_jurisdiction
        CHECK (jurisdiction IN ('NYC', 'LA', 'DC', 'MD'))
);

COMMENT ON TABLE fact_detention IS
'One row per detention event. The heart of the project. Every number here
represents a person who was caged — many of them for something they did not do,
or something that should never have been a crime.';

COMMENT ON COLUMN fact_detention.work_days_to_bail IS
'bail_set_amount / median_daily_income from home ZIP.
The number of full work-days someone must earn just to go home.';

COMMENT ON COLUMN fact_detention.pretrial_detention_flag IS
'TRUE = legally innocent person being held because they cannot afford bail.
This is the central injustice this project documents.';

COMMENT ON COLUMN fact_detention.case_disposition IS
'What ultimately happened. Guilty Plea after long pretrial detention strongly
suggests coercion — not guilt.';


-- ── Indexes ───────────────────────────────────────────────────────────────────

CREATE INDEX idx_fact_booking_date      ON fact_detention (booking_date DESC);
CREATE INDEX idx_fact_jurisdiction      ON fact_detention (jurisdiction);
CREATE INDEX idx_fact_bail_type         ON fact_detention (bail_type);
CREATE INDEX idx_fact_pretrial          ON fact_detention (pretrial_detention_flag)
    WHERE pretrial_detention_flag = TRUE;
CREATE INDEX idx_fact_md_reform         ON fact_detention (is_md_reform_case, booking_date)
    WHERE jurisdiction = 'MD';
CREATE INDEX idx_fact_poverty_charges   ON fact_detention (primary_charge_key);
CREATE INDEX idx_geo_zip                ON dim_geography (zip_code);
CREATE INDEX idx_charge_category        ON dim_charges (charge_category);
CREATE INDEX idx_charge_poverty         ON dim_charges (is_poverty_linked) WHERE is_poverty_linked = TRUE;
CREATE INDEX idx_charge_addiction       ON dim_charges (is_addiction_related) WHERE is_addiction_related = TRUE;
CREATE INDEX idx_inmate_hash            ON dim_inmate (inmate_id_hash);


-- ── Materialized View: Bail Gap by ZIP ────────────────────────────────────────
-- Pre-computed for dashboard performance.
-- This is what gets displayed on the heatmap.

CREATE MATERIALIZED VIEW mv_bail_gap_by_zip AS
SELECT
    g.zip_code,
    g.jurisdiction,
    g.city,
    g.median_household_income,
    g.median_daily_income,
    g.poverty_rate_pct,
    g.pct_black,
    g.eviction_rate_per_100,
    COUNT(fd.detention_key)                                     AS total_bookings,
    SUM(CASE WHEN fd.pretrial_detention_flag THEN 1 ELSE 0 END) AS pretrial_detained,
    ROUND(
        100.0 * SUM(CASE WHEN fd.pretrial_detention_flag THEN 1 ELSE 0 END)
        / NULLIF(COUNT(fd.detention_key), 0), 2
    )                                                           AS pretrial_rate_pct,
    ROUND(AVG(fd.bail_set_amount) FILTER (
        WHERE fd.bail_set_amount IS NOT NULL AND fd.bail_set_amount > 0
    ), 0)                                                       AS avg_bail_amount,
    ROUND(AVG(fd.work_days_to_bail) FILTER (
        WHERE fd.work_days_to_bail IS NOT NULL
    ), 1)                                                       AS avg_work_days_to_bail,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY fd.work_days_to_bail
    ) FILTER (WHERE fd.work_days_to_bail IS NOT NULL), 1)       AS median_work_days_to_bail,
    ROUND(AVG(fd.detention_length_days) FILTER (
        WHERE fd.detention_length_days IS NOT NULL
    ), 0)                                                       AS avg_detention_days
FROM fact_detention fd
JOIN dim_geography g ON fd.home_geo_key = g.geo_key
GROUP BY g.zip_code, g.jurisdiction, g.city, g.median_household_income,
         g.median_daily_income, g.poverty_rate_pct, g.pct_black, g.eviction_rate_per_100
WITH DATA;

CREATE UNIQUE INDEX ON mv_bail_gap_by_zip (zip_code);

COMMENT ON MATERIALIZED VIEW mv_bail_gap_by_zip IS
'Pre-computed bail gap metrics by ZIP. Refresh with: REFRESH MATERIALIZED VIEW mv_bail_gap_by_zip;';


-- ── Materialized View: Innocence by Jurisdiction ──────────────────────────────

CREATE MATERIALIZED VIEW mv_innocence_by_jurisdiction AS
SELECT
    jurisdiction,
    COUNT(*)                                                    AS total_detained,
    SUM(CASE WHEN pretrial_detention_flag THEN 1 ELSE 0 END)    AS legally_innocent,
    ROUND(
        100.0 * SUM(CASE WHEN pretrial_detention_flag THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 1
    )                                                           AS pct_legally_innocent,
    SUM(CASE WHEN bail_set_amount <= 500
             AND pretrial_detention_flag THEN 1 ELSE 0 END)     AS held_under_500_bail,
    SUM(CASE WHEN bail_set_amount <= 1000
             AND pretrial_detention_flag THEN 1 ELSE 0 END)     AS held_under_1000_bail,
    ROUND(AVG(detention_length_days) FILTER (
        WHERE pretrial_detention_flag AND detention_length_days IS NOT NULL
    ), 0)                                                       AS avg_pretrial_days,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY detention_length_days
    ) FILTER (WHERE pretrial_detention_flag), 0)                AS median_pretrial_days
FROM fact_detention
GROUP BY jurisdiction
WITH DATA;

CREATE UNIQUE INDEX ON mv_innocence_by_jurisdiction (jurisdiction);


-- ── Staging: Deaths in Custody ────────────────────────────────────────────────
-- Load from Marshall Project CSV (see docs/SOURCES.md).
-- \copy stg_deaths_in_custody FROM 'data/marshall_deaths.csv' CSV HEADER

CREATE TABLE stg_deaths_in_custody (
    death_id            SERIAL PRIMARY KEY,
    facility_name       VARCHAR(200),
    jurisdiction        VARCHAR(20),
    death_date          DATE,
    manner_of_death     VARCHAR(100),   -- Natural, Suicide, Homicide, Accident, Unknown
    conviction_status   VARCHAR(50),    -- Pretrial, Sentenced, Unknown
    age_at_death        INTEGER,
    gender              VARCHAR(20),
    race_ethnicity      VARCHAR(50),
    charge_at_death     VARCHAR(200),
    days_detained       INTEGER,
    source              VARCHAR(100) DEFAULT 'Marshall Project',
    source_url          TEXT
);
