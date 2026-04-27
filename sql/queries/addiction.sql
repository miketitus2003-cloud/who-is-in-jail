-- ============================================================
-- QUERY: Addiction Behind Bars
-- ============================================================
-- Addiction is a medical condition.
-- We respond to it with cages.
--
-- This query documents how many people are locked up for
-- something that belongs in a doctor's office, not a courtroom.
-- It also shows the cycle: when people get out with a record,
-- they can't get housing or work — which makes recovery harder,
-- not easier.
-- ============================================================

-- ── Part 1: The scale — how many people are here for addiction? ───────────────

SELECT
    fd.jurisdiction,
    c.charge_description,
    c.charge_class,
    COUNT(*)                                                    AS people_locked_up,
    -- How many couldn't make bail and sat pretrial?
    SUM(CASE WHEN fd.pretrial_detention_flag THEN 1 ELSE 0 END) AS held_pretrial,
    ROUND(100.0 * SUM(CASE WHEN fd.pretrial_detention_flag THEN 1 ELSE 0 END)
          / NULLIF(COUNT(*), 0), 1)                             AS pct_held_pretrial,
    -- Bail amounts
    ROUND(AVG(fd.bail_set_amount) FILTER (
        WHERE fd.bail_set_amount > 0
    ), 0)                                                       AS avg_bail_set,
    -- Time in cage
    ROUND(AVG(fd.detention_length_days), 0)                     AS avg_days_detained,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY fd.detention_length_days
    ), 0)                                                       AS median_days_detained,
    ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (
        ORDER BY fd.detention_length_days
    ), 0)                                                       AS p90_days_detained,
    -- Work-days-to-freedom
    ROUND(AVG(fd.work_days_to_bail), 1)                         AS avg_work_days_to_bail,
    -- Neighborhood income of people being locked up for addiction
    ROUND(AVG(g.median_household_income), 0)                    AS avg_neighborhood_income,
    -- Rank: which charges send the most people to jail for addiction?
    RANK() OVER (
        PARTITION BY fd.jurisdiction
        ORDER BY COUNT(*) DESC
    )                                                           AS volume_rank
FROM fact_detention fd
JOIN dim_charges   c ON fd.primary_charge_key = c.charge_key
JOIN dim_geography g ON fd.home_geo_key       = g.geo_key
WHERE
    c.is_addiction_related = TRUE
    AND fd.booking_date >= CURRENT_DATE - INTERVAL '3 years'
GROUP BY fd.jurisdiction, c.charge_description, c.charge_class
HAVING COUNT(*) >= 20
ORDER BY fd.jurisdiction, people_locked_up DESC;


-- ── Part 2: Possession vs. Treatment availability by ZIP ─────────────────────
-- The ZIPs with the highest addiction-related arrest rates —
-- are they also the ZIPs with the lowest income?
-- That's not a coincidence. That's the system.

WITH addiction_by_zip AS (
    SELECT
        g.zip_code,
        g.jurisdiction,
        g.city,
        g.median_household_income,
        g.median_daily_income,
        g.poverty_rate_pct,
        g.pct_black,
        g.eviction_rate_per_100,
        COUNT(*)                                                AS addiction_arrests,
        SUM(CASE WHEN fd.pretrial_detention_flag THEN 1 ELSE 0 END)
                                                                AS pretrial_detained,
        ROUND(AVG(fd.bail_set_amount) FILTER (
            WHERE fd.bail_set_amount > 0
        ), 0)                                                   AS avg_bail,
        ROUND(AVG(fd.work_days_to_bail), 1)                     AS avg_work_days_to_bail,
        ROUND(AVG(fd.detention_length_days), 0)                 AS avg_days_detained
    FROM fact_detention fd
    JOIN dim_charges   c ON fd.primary_charge_key = c.charge_key
    JOIN dim_geography g ON fd.home_geo_key       = g.geo_key
    WHERE
        c.is_addiction_related = TRUE
        AND fd.booking_date >= CURRENT_DATE - INTERVAL '3 years'
    GROUP BY g.zip_code, g.jurisdiction, g.city, g.median_household_income,
             g.median_daily_income, g.poverty_rate_pct, g.pct_black, g.eviction_rate_per_100
)
SELECT
    *,
    -- How does this ZIP rank for addiction arrests within its jurisdiction?
    RANK() OVER (
        PARTITION BY jurisdiction
        ORDER BY addiction_arrests DESC
    )                                                           AS addiction_arrest_rank,
    -- Is there a correlation between poverty and addiction arrests?
    ROUND(
        (median_household_income - AVG(median_household_income) OVER (PARTITION BY jurisdiction))
        / NULLIF(STDDEV(median_household_income) OVER (PARTITION BY jurisdiction), 0),
    2)                                                          AS income_z_score
FROM addiction_by_zip
WHERE addiction_arrests >= 10
ORDER BY jurisdiction, addiction_arrests DESC;


-- ── Part 3: The Repeat Cycle ──────────────────────────────────────────────────
-- How many people appear in this data multiple times on addiction charges?
-- This is the cycle. No treatment. Out. Re-arrested. Back inside.
-- The system profits from treating addiction as crime.

WITH person_appearances AS (
    SELECT
        i.inmate_id_hash,
        i.age_bucket,
        i.gender,
        i.race_ethnicity,
        fd.jurisdiction,
        COUNT(*)                                                AS total_addiction_bookings,
        MIN(fd.booking_date)                                    AS first_booking,
        MAX(fd.booking_date)                                    AS most_recent_booking,
        MAX(fd.booking_date) - MIN(fd.booking_date)            AS days_in_cycle,
        SUM(fd.detention_length_days)                           AS total_days_detained_lifetime,
        ROUND(AVG(fd.bail_set_amount) FILTER (
            WHERE fd.bail_set_amount > 0
        ), 0)                                                   AS avg_bail_each_time
    FROM fact_detention fd
    JOIN dim_inmate  i ON fd.inmate_key         = i.inmate_key
    JOIN dim_charges c ON fd.primary_charge_key = c.charge_key
    WHERE c.is_addiction_related = TRUE
    GROUP BY i.inmate_id_hash, i.age_bucket, i.gender, i.race_ethnicity, fd.jurisdiction
)
SELECT
    jurisdiction,
    age_bucket,
    gender,
    race_ethnicity,
    -- People stuck in the cycle (2+ bookings)
    COUNT(*) FILTER (WHERE total_addiction_bookings >= 2) AS people_in_cycle,
    -- Deep in the cycle (4+ bookings)
    COUNT(*) FILTER (WHERE total_addiction_bookings >= 4) AS people_deep_in_cycle,
    ROUND(AVG(total_addiction_bookings), 1)                     AS avg_bookings_per_person,
    ROUND(AVG(total_days_detained_lifetime) FILTER (
        WHERE total_addiction_bookings >= 2
    ), 0)                                                       AS avg_lifetime_days_detained,
    ROUND(AVG(days_in_cycle) FILTER (
        WHERE total_addiction_bookings >= 2
    ), 0)                                                       AS avg_days_in_cycle,
    -- Window: rank jurisdictions by repeat-cycle severity
    RANK() OVER (
        ORDER BY AVG(total_addiction_bookings) DESC
    )                                                           AS cycle_severity_rank
FROM person_appearances
GROUP BY jurisdiction, age_bucket, gender, race_ethnicity
HAVING COUNT(*) >= 5
ORDER BY jurisdiction, people_in_cycle DESC;
