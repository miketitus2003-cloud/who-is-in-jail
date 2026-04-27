-- ============================================================
-- QUERY: Conditions Inside — Deaths, Overcrowding, Violence
-- ============================================================
-- People talk about "jail" like it's a neutral holding place.
-- It is not.
--
-- Rikers Island has been under federal investigation for years.
-- People have died there waiting for trial.
-- People have been beaten there while legally innocent.
-- LA County has documented deputy gangs operating inside the facility.
--
-- This query pulls the conditions data that makes those facts visible:
-- deaths in custody, overcrowding levels, use of force incidents.
-- These numbers represent real people. Many of them never convicted.
-- ============================================================

-- ── Part 1: Facility-level conditions snapshot ────────────────────────────────

SELECT
    f.facility_name,
    f.jurisdiction,
    f.facility_type,
    f.rated_capacity,
    f.federal_oversight,
    f.oversight_reason,
    f.deaths_in_custody_ytd,
    f.use_of_force_incidents_ytd,
    f.solitary_population,

    -- Current population from fact table
    COUNT(fd.detention_key) FILTER (
        WHERE fd.release_date IS NULL
    )                                                           AS current_population,

    -- Capacity utilization
    ROUND(
        100.0 * COUNT(fd.detention_key) FILTER (WHERE fd.release_date IS NULL)
        / NULLIF(f.rated_capacity, 0), 1
    )                                                           AS capacity_pct,

    CASE
        WHEN ROUND(100.0 * COUNT(fd.detention_key) FILTER (WHERE fd.release_date IS NULL)
             / NULLIF(f.rated_capacity, 0), 1) > 130 THEN 'CRITICAL OVERCROWDING'
        WHEN ROUND(100.0 * COUNT(fd.detention_key) FILTER (WHERE fd.release_date IS NULL)
             / NULLIF(f.rated_capacity, 0), 1) > 110 THEN 'Overcrowded'
        WHEN ROUND(100.0 * COUNT(fd.detention_key) FILTER (WHERE fd.release_date IS NULL)
             / NULLIF(f.rated_capacity, 0), 1) > 90  THEN 'Near Capacity'
        ELSE 'Within Capacity'
    END                                                         AS capacity_status,

    -- What % of current population is pretrial (legally innocent)?
    ROUND(100.0 * COUNT(fd.detention_key) FILTER (
        WHERE fd.release_date IS NULL AND fd.pretrial_detention_flag
    ) / NULLIF(COUNT(fd.detention_key) FILTER (WHERE fd.release_date IS NULL), 0), 1)
                                                                AS pct_pretrial_in_facility,

    -- Average length of stay
    ROUND(AVG(fd.detention_length_days) FILTER (
        WHERE fd.detention_length_days IS NOT NULL
    ), 0)                                                       AS alos_days,

    -- Deaths per 1,000 detainees (normalized)
    ROUND(1000.0 * f.deaths_in_custody_ytd
          / NULLIF(COUNT(fd.detention_key) FILTER (WHERE fd.release_date IS NULL), 0), 2)
                                                                AS deaths_per_1000_detainees

FROM dim_facility f
LEFT JOIN fact_detention fd ON f.facility_key = fd.facility_key
GROUP BY f.facility_key, f.facility_name, f.jurisdiction, f.facility_type,
         f.rated_capacity, f.federal_oversight, f.oversight_reason,
         f.deaths_in_custody_ytd, f.use_of_force_incidents_ytd, f.solitary_population
ORDER BY capacity_pct DESC NULLS LAST;


-- ── Part 2: Deaths in custody — who died and while doing what? ───────────────
-- People who died while legally innocent.
-- People who died for a $500 bail they couldn't pay.
-- This query makes that count visible.

SELECT
    f.facility_name,
    f.jurisdiction,
    i.age_bucket,
    i.gender,
    i.race_ethnicity,
    c.charge_category,
    c.is_violent,
    c.is_poverty_linked,
    c.is_addiction_related,
    fd.pretrial_detention_flag,
    fd.bail_set_amount,
    fd.detention_length_days                                    AS days_detained_before_death,
    fd.bail_type,
    -- Were they legally innocent when they died?
    CASE WHEN fd.pretrial_detention_flag THEN 'Legally Innocent' ELSE 'Post-Conviction' END
                                                                AS conviction_status_at_death
FROM fact_detention fd
JOIN dim_facility  f ON fd.facility_key       = f.facility_key
JOIN dim_inmate    i ON fd.inmate_key         = i.inmate_key
JOIN dim_charges   c ON fd.primary_charge_key = c.charge_key
-- stg_deaths_in_custody is loaded from the Marshall Project CSV (see docs/SOURCES.md)
-- Load it with: psql -d jail_data -c "\copy stg_deaths_in_custody FROM 'data/marshall_deaths.csv' CSV HEADER"
-- Then: JOIN stg_deaths_in_custody d ON d.booking_id_hash = i.inmate_id_hash
-- Until that data is loaded, this returns current in-custody population as a proxy
WHERE
    fd.release_date IS NULL
ORDER BY fd.detention_length_days DESC NULLS LAST;


-- ── Part 3: Overcrowding trend — 90-day rolling census vs. capacity ───────────
-- Shows when facilities crossed the line from strained to crisis.
-- Every person above rated capacity is a person in worse conditions.

WITH daily_census AS (
    SELECT
        fd.facility_key,
        fd.booking_date                                         AS census_date,
        COUNT(*) FILTER (
            WHERE fd.release_date IS NULL
               OR fd.release_date > fd.booking_date
        )                                                       AS population_estimate
    FROM fact_detention fd
    WHERE fd.booking_date >= CURRENT_DATE - INTERVAL '180 days'
    GROUP BY fd.facility_key, fd.booking_date
)
SELECT
    f.facility_name,
    f.jurisdiction,
    f.rated_capacity,
    dc.census_date,
    dc.population_estimate,
    ROUND(100.0 * dc.population_estimate / NULLIF(f.rated_capacity, 0), 1)
                                                                AS capacity_pct,
    -- 7-day rolling average (smooth daily noise)
    ROUND(AVG(dc.population_estimate) OVER (
        PARTITION BY f.facility_key
        ORDER BY dc.census_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 0)                                                       AS rolling_7day_population,
    -- 30-day rolling max (worst-case)
    MAX(dc.population_estimate) OVER (
        PARTITION BY f.facility_key
        ORDER BY dc.census_date
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    )                                                           AS rolling_30day_peak,
    -- Days over capacity this month
    SUM(CASE WHEN dc.population_estimate > f.rated_capacity THEN 1 ELSE 0 END) OVER (
        PARTITION BY f.facility_key
        ORDER BY dc.census_date
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    )                                                           AS days_overcrowded_last_30
FROM daily_census dc
JOIN dim_facility f ON dc.facility_key = f.facility_key
ORDER BY f.jurisdiction, f.facility_name, dc.census_date DESC;


-- ── Part 4: Solitary confinement — who is being isolated? ─────────────────────
-- Solitary confinement has been classified as torture by the UN.
-- People are put in it for 23 hours a day. Sometimes for years.
-- Sometimes while legally innocent.
-- This query shows who is in solitary and what they're charged with.

SELECT
    f.facility_name,
    f.jurisdiction,
    f.solitary_population,
    ROUND(100.0 * f.solitary_population
          / NULLIF(COUNT(fd.detention_key) FILTER (WHERE fd.release_date IS NULL), 0), 1)
                                                                AS pct_population_in_solitary,
    -- Pretrial in solitary: legally innocent and in isolation
    COUNT(fd.detention_key) FILTER (
        WHERE fd.pretrial_detention_flag AND fd.release_date IS NULL
    )                                                           AS pretrial_in_facility,
    -- Most common charges in this facility
    MODE() WITHIN GROUP (ORDER BY c.charge_category)            AS most_common_charge_category,
    ROUND(AVG(fd.detention_length_days) FILTER (
        WHERE fd.detention_length_days IS NOT NULL
    ), 0)                                                       AS avg_alos
FROM dim_facility f
JOIN fact_detention fd ON f.facility_key      = fd.facility_key
JOIN dim_charges    c  ON fd.primary_charge_key = c.charge_key
WHERE f.solitary_population IS NOT NULL
GROUP BY f.facility_key, f.facility_name, f.jurisdiction, f.solitary_population
ORDER BY pct_population_in_solitary DESC;
