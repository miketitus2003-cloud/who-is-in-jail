-- ============================================================
-- QUERY: The Bail Gap
-- ============================================================
-- "How many days does someone have to work
--  just to buy their own freedom?"
--
-- Same charge. Same bail amount.
-- In a wealthy ZIP: you're out in a day.
-- In a poor ZIP: you're in a cage for weeks.
-- That's not justice. That's the price of being poor.
-- ============================================================

-- ── Part 1: Work-days-to-bail by ZIP, ranked ──────────────────────────────────
WITH bail_events AS (
    SELECT
        fd.detention_key,
        fd.jurisdiction,
        fd.bail_set_amount,
        fd.booking_date,
        fd.pretrial_detention_flag,
        fd.detention_length_days,
        fd.work_days_to_bail,
        g.zip_code,
        g.city,
        g.median_household_income,
        g.median_daily_income,
        g.poverty_rate_pct,
        g.pct_children_single_parent,
        g.pct_severely_rent_burdened,
        g.pct_black,
        g.eviction_rate_per_100,
        c.charge_category,
        c.is_poverty_linked,
        c.is_addiction_related
    FROM fact_detention fd
    JOIN dim_geography g ON fd.home_geo_key       = g.geo_key
    JOIN dim_charges   c ON fd.primary_charge_key = c.charge_key
    WHERE
        fd.bail_set_amount > 0
        AND g.median_daily_income > 0
        AND fd.booking_date >= '2020-01-01'
),
zip_summary AS (
    SELECT
        zip_code,
        city,
        jurisdiction,
        median_household_income,
        median_daily_income,
        poverty_rate_pct,
        pct_children_single_parent,
        pct_severely_rent_burdened,
        pct_black,
        eviction_rate_per_100,
        COUNT(*)                                                AS total_bail_cases,
        ROUND(AVG(bail_set_amount), 0)                          AS avg_bail_set,
        ROUND(AVG(work_days_to_bail), 1)                        AS avg_work_days_to_bail,
        ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY work_days_to_bail
        ), 1)                                                   AS median_work_days_to_bail,
        ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (
            ORDER BY work_days_to_bail
        ), 1)                                                   AS p90_work_days_to_bail,
        ROUND(100.0 * SUM(CASE WHEN pretrial_detention_flag THEN 1 ELSE 0 END)
              / NULLIF(COUNT(*), 0), 1)                         AS pretrial_detention_rate,
        ROUND(100.0 * SUM(CASE WHEN is_poverty_linked THEN 1 ELSE 0 END)
              / NULLIF(COUNT(*), 0), 1)                         AS pct_poverty_charges,
        ROUND(100.0 * SUM(CASE WHEN is_addiction_related THEN 1 ELSE 0 END)
              / NULLIF(COUNT(*), 0), 1)                         AS pct_addiction_charges,
        ROUND(AVG(detention_length_days) FILTER (
            WHERE pretrial_detention_flag
        ), 0)                                                   AS avg_pretrial_days
    FROM bail_events
    GROUP BY zip_code, city, jurisdiction, median_household_income,
             median_daily_income, poverty_rate_pct, pct_children_single_parent,
             pct_severely_rent_burdened, pct_black, eviction_rate_per_100
    HAVING COUNT(*) >= 20   -- Only ZIPs with enough cases to be meaningful
)
SELECT
    zip_code,
    city,
    jurisdiction,
    median_household_income,
    median_daily_income,
    avg_bail_set,
    avg_work_days_to_bail,
    median_work_days_to_bail,
    p90_work_days_to_bail,
    poverty_rate_pct,
    pct_children_single_parent,
    pct_severely_rent_burdened,
    pct_black,
    eviction_rate_per_100,
    pretrial_detention_rate,
    pct_poverty_charges,
    pct_addiction_charges,
    avg_pretrial_days,
    total_bail_cases,

    -- Rank the worst bail gaps within each jurisdiction
    RANK() OVER (
        PARTITION BY jurisdiction
        ORDER BY avg_work_days_to_bail DESC
    )                                                           AS bail_gap_rank,

    -- Z-score: how extreme is this ZIP compared to its city's average?
    ROUND(
        (avg_work_days_to_bail
            - AVG(avg_work_days_to_bail) OVER (PARTITION BY jurisdiction))
        / NULLIF(STDDEV(avg_work_days_to_bail) OVER (PARTITION BY jurisdiction), 0),
    2)                                                          AS bail_gap_z_score,

    -- "Compounded disadvantage" — ZIPs where poverty AND bail gap AND eviction overlap
    CASE
        WHEN poverty_rate_pct > 25
         AND avg_work_days_to_bail > 30
         AND eviction_rate_per_100 > 5
        THEN TRUE
        ELSE FALSE
    END                                                         AS compounded_disadvantage_zone

FROM zip_summary
ORDER BY jurisdiction, avg_work_days_to_bail DESC;


-- ── Part 2: The $500 Question ─────────────────────────────────────────────────
-- $500 bail: how many days of work is that in each jurisdiction?
-- The same dollar amount means completely different things in different ZIPs.

SELECT
    jurisdiction,
    COUNT(DISTINCT zip_code)                                    AS zip_codes_analyzed,
    ROUND(AVG(median_household_income), 0)                      AS jurisdiction_avg_income,
    ROUND(AVG(median_daily_income), 2)                          AS jurisdiction_avg_daily_income,
    -- How many work-days for a $500 bail in an average ZIP?
    ROUND(500.0 / NULLIF(AVG(median_daily_income), 0), 1)       AS work_days_for_500_bail,
    -- How many work-days for a $1,000 bail?
    ROUND(1000.0 / NULLIF(AVG(median_daily_income), 0), 1)      AS work_days_for_1000_bail,
    -- How many work-days for a $5,000 bail?
    ROUND(5000.0 / NULLIF(AVG(median_daily_income), 0), 1)      AS work_days_for_5000_bail,
    -- For context: federal minimum wage = ~$58/day
    ROUND(500.0 / 58.0, 1)                                      AS work_days_at_min_wage_for_500,
    ROUND(1000.0 / 58.0, 1)                                     AS work_days_at_min_wage_for_1000
FROM mv_bail_gap_by_zip
GROUP BY jurisdiction
ORDER BY jurisdiction_avg_income ASC;   -- Poorest jurisdictions first


-- ── Part 3: Bail Gap vs. Eviction Rate (the housing-to-jail pipeline) ─────────
-- When people get evicted, they end up on the street.
-- When they're on the street, they get arrested.
-- When they get arrested, they can't make bail.
-- When they can't make bail, they lose what little they had left.
-- This query shows that pipeline in the data.

SELECT
    g.zip_code,
    g.jurisdiction,
    g.eviction_rate_per_100,
    g.median_household_income,
    g.pct_severely_rent_burdened,
    m.avg_work_days_to_bail,
    m.pretrial_rate_pct,
    m.total_bookings,
    -- Correlation proxy: rank both metrics and compare
    RANK() OVER (PARTITION BY g.jurisdiction ORDER BY g.eviction_rate_per_100 DESC)
                                                                AS eviction_rank,
    RANK() OVER (PARTITION BY g.jurisdiction ORDER BY m.avg_work_days_to_bail DESC)
                                                                AS bail_gap_rank,
    -- ZIPs where both eviction AND bail gap are in the top quartile
    CASE WHEN g.eviction_rate_per_100 >= PERCENTILE_CONT(0.75) WITHIN GROUP (
                ORDER BY g.eviction_rate_per_100
             ) OVER (PARTITION BY g.jurisdiction)
          AND m.avg_work_days_to_bail >= PERCENTILE_CONT(0.75) WITHIN GROUP (
                ORDER BY m.avg_work_days_to_bail
             ) OVER (PARTITION BY g.jurisdiction)
         THEN TRUE ELSE FALSE
    END                                                         AS housing_to_jail_pipeline_zone
FROM dim_geography g
JOIN mv_bail_gap_by_zip m ON g.zip_code = m.zip_code
WHERE g.eviction_rate_per_100 IS NOT NULL
ORDER BY g.jurisdiction, g.eviction_rate_per_100 DESC;
