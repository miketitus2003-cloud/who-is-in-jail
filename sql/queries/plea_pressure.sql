-- ============================================================
-- QUERY: The Plea Trap
-- ============================================================
-- The longer someone sits in pretrial detention, the more
-- pressure they face to plead guilty — whether or not they are.
--
-- The offer is always the same:
-- "Plead guilty right now. Go home today."
-- "Or stay here, wait for trial, and risk more time if you lose."
--
-- Most people take the deal. Not because they're guilty.
-- Because the alternative is unbearable.
--
-- This query makes that coercion visible in the data.
-- ============================================================

-- ── Part 1: Disposition by detention length bucket ────────────────────────────
-- If the system were fair, guilt pleas would be spread evenly
-- across detention lengths. They're not.
-- Guilty pleas spike after extended pretrial detention.
-- That spike IS the coercion.

WITH detention_buckets AS (
    SELECT
        fd.jurisdiction,
        fd.detention_length_days,
        fd.case_disposition,
        fd.bail_set_amount,
        fd.work_days_to_bail,
        c.charge_category,
        c.is_violent,
        c.is_poverty_linked,
        g.median_household_income,

        CASE
            WHEN fd.detention_length_days BETWEEN 0  AND 7   THEN '01: 0-7 days'
            WHEN fd.detention_length_days BETWEEN 8  AND 30  THEN '02: 8-30 days'
            WHEN fd.detention_length_days BETWEEN 31 AND 90  THEN '03: 1-3 months'
            WHEN fd.detention_length_days BETWEEN 91 AND 180 THEN '04: 3-6 months'
            WHEN fd.detention_length_days BETWEEN 181 AND 365 THEN '05: 6-12 months'
            WHEN fd.detention_length_days > 365              THEN '06: Over a year'
            ELSE 'Unknown'
        END                                             AS time_in_cage

    FROM fact_detention fd
    JOIN dim_charges   c ON fd.primary_charge_key = c.charge_key
    JOIN dim_geography g ON fd.home_geo_key       = g.geo_key
    WHERE
        fd.pretrial_detention_flag = TRUE
        AND fd.case_disposition IS NOT NULL
        AND fd.booking_date >= '2018-01-01'
)
SELECT
    time_in_cage,
    jurisdiction,
    charge_category,
    COUNT(*)                                                    AS total_cases,

    -- Guilty pleas: the plea trap
    SUM(CASE WHEN case_disposition = 'Guilty Plea' THEN 1 ELSE 0 END)
                                                                AS guilty_pleas,
    ROUND(100.0 * SUM(CASE WHEN case_disposition = 'Guilty Plea' THEN 1 ELSE 0 END)
          / NULLIF(COUNT(*), 0), 1)                             AS guilty_plea_rate,

    -- Acquittals and dismissals: people who were innocent and survived
    SUM(CASE WHEN case_disposition IN ('Trial - Not Guilty', 'Dismissed', 'Nolle Prosequi', 'ACD')
             THEN 1 ELSE 0 END)                                 AS exonerated_or_dismissed,
    ROUND(100.0 * SUM(CASE WHEN case_disposition IN ('Trial - Not Guilty','Dismissed','Nolle Prosequi','ACD')
             THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 1)       AS exoneration_rate,

    ROUND(AVG(bail_set_amount), 0)                              AS avg_bail,
    ROUND(AVG(work_days_to_bail), 1)                            AS avg_work_days_to_bail,
    ROUND(AVG(median_household_income), 0)                      AS avg_neighborhood_income,

    -- How many were poverty-linked charges?
    ROUND(100.0 * SUM(CASE WHEN is_poverty_linked THEN 1 ELSE 0 END)
          / NULLIF(COUNT(*), 0), 1)                             AS pct_poverty_charges

FROM detention_buckets
GROUP BY time_in_cage, jurisdiction, charge_category
ORDER BY jurisdiction, time_in_cage, total_cases DESC;


-- ── Part 2: The Innocence Tax ─────────────────────────────────────────────────
-- People who were eventually acquitted or had charges dismissed —
-- how long did they sit in cage for something they didn't do?
-- This is the cost of being innocent but poor.

SELECT
    fd.jurisdiction,
    c.charge_category,
    c.charge_description,
    COUNT(*)                                                    AS wrongly_detained,
    ROUND(AVG(fd.detention_length_days), 0)                     AS avg_days_wrongly_detained,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY fd.detention_length_days
    ), 0)                                                       AS median_days_wrongly_detained,
    MAX(fd.detention_length_days)                               AS max_days_wrongly_detained,
    ROUND(AVG(fd.bail_set_amount), 0)                           AS avg_bail_that_kept_them_in,
    -- Total person-days lost to wrongful pretrial detention
    SUM(fd.detention_length_days)                               AS total_person_days_lost,
    -- Translate to years of human life
    ROUND(SUM(fd.detention_length_days) / 365.0, 1)             AS years_of_life_lost

FROM fact_detention fd
JOIN dim_charges c ON fd.primary_charge_key = c.charge_key
WHERE
    fd.pretrial_detention_flag = TRUE
    AND fd.case_disposition IN ('Trial - Not Guilty', 'Dismissed', 'Nolle Prosequi', 'ACD')
    AND fd.detention_length_days > 0
    AND fd.booking_date >= '2018-01-01'
GROUP BY fd.jurisdiction, c.charge_category, c.charge_description
HAVING COUNT(*) >= 10
ORDER BY avg_days_wrongly_detained DESC;


-- ── Part 3: The Poverty Premium ──────────────────────────────────────────────
-- Same charge. Different ZIP code income. Completely different outcome.
-- This is the system's thumb on the scale.

WITH income_quintiles AS (
    SELECT
        fd.detention_key,
        fd.jurisdiction,
        fd.bail_set_amount,
        fd.detention_length_days,
        fd.case_disposition,
        fd.work_days_to_bail,
        c.charge_category,
        c.is_poverty_linked,
        g.median_household_income,
        NTILE(5) OVER (
            PARTITION BY fd.jurisdiction
            ORDER BY g.median_household_income
        )                                                       AS income_quintile
    FROM fact_detention fd
    JOIN dim_charges   c ON fd.primary_charge_key = c.charge_key
    JOIN dim_geography g ON fd.home_geo_key       = g.geo_key
    WHERE
        fd.pretrial_detention_flag = TRUE
        AND fd.booking_date >= '2018-01-01'
)
SELECT
    income_quintile,
    jurisdiction,
    CASE income_quintile
        WHEN 1 THEN 'Poorest 20%'
        WHEN 2 THEN 'Lower-Middle 20%'
        WHEN 3 THEN 'Middle 20%'
        WHEN 4 THEN 'Upper-Middle 20%'
        WHEN 5 THEN 'Wealthiest 20%'
    END                                                         AS income_group,
    ROUND(AVG(median_household_income), 0)                      AS avg_income_in_group,
    COUNT(*)                                                    AS cases,
    ROUND(AVG(bail_set_amount), 0)                              AS avg_bail,
    ROUND(AVG(work_days_to_bail), 1)                            AS avg_work_days_to_bail,
    ROUND(AVG(detention_length_days), 0)                        AS avg_days_detained,
    ROUND(100.0 * SUM(CASE WHEN case_disposition = 'Guilty Plea' THEN 1 ELSE 0 END)
          / NULLIF(COUNT(*), 0), 1)                             AS guilty_plea_rate,
    ROUND(100.0 * SUM(CASE WHEN is_poverty_linked THEN 1 ELSE 0 END)
          / NULLIF(COUNT(*), 0), 1)                             AS pct_poverty_charges
FROM income_quintiles
GROUP BY income_quintile, jurisdiction
ORDER BY jurisdiction, income_quintile;
