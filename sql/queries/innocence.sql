-- ============================================================
-- QUERY: The Innocence Numbers
-- ============================================================
-- "How many people sitting in jail right now have never been
--  convicted of anything?"
--
-- These are legally innocent people. Held not because they
-- were found guilty of anything — but because they were poor.
-- The system calls it "pretrial detention."
-- What it actually is: punishment before trial.
-- ============================================================

-- ── Part 1: Top-line innocence by jurisdiction ────────────────────────────────
WITH current_population AS (
    SELECT
        fd.jurisdiction,
        COUNT(*)                                                AS total_detained,

        -- Legally innocent: charged but not convicted, bail not paid
        SUM(CASE WHEN fd.pretrial_detention_flag THEN 1 ELSE 0 END)
                                                                AS legally_innocent,

        -- Held for under $500 — lost everything for less than a car payment
        SUM(CASE WHEN fd.pretrial_detention_flag
                 AND fd.bail_set_amount > 0
                 AND fd.bail_set_amount <= 500 THEN 1 ELSE 0 END)
                                                                AS held_under_500,

        -- Held for under $1,000
        SUM(CASE WHEN fd.pretrial_detention_flag
                 AND fd.bail_set_amount > 0
                 AND fd.bail_set_amount <= 1000 THEN 1 ELSE 0 END)
                                                                AS held_under_1000,

        -- Held with NO bail set at all (remand — judge decided they stay regardless)
        SUM(CASE WHEN fd.bail_type = 'Remand' THEN 1 ELSE 0 END)
                                                                AS held_on_remand,

        -- How long have they been waiting?
        ROUND(AVG(fd.detention_length_days) FILTER (
            WHERE fd.pretrial_detention_flag
        ), 0)                                                   AS avg_days_waiting,

        ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY fd.detention_length_days
        ) FILTER (WHERE fd.pretrial_detention_flag), 0)         AS median_days_waiting,

        -- Worst cases: over 6 months pretrial — legally innocent
        SUM(CASE WHEN fd.pretrial_detention_flag
                 AND fd.detention_length_days > 180 THEN 1 ELSE 0 END)
                                                                AS over_6_months_pretrial,

        -- Over a year pretrial — never convicted of anything
        SUM(CASE WHEN fd.pretrial_detention_flag
                 AND fd.detention_length_days > 365 THEN 1 ELSE 0 END)
                                                                AS over_1_year_pretrial

    FROM fact_detention fd
    WHERE fd.booking_date >= CURRENT_DATE - INTERVAL '1 year'
),
with_rates AS (
    SELECT
        *,
        ROUND(100.0 * legally_innocent / NULLIF(total_detained, 0), 1)
                                                                AS pct_legally_innocent,
        ROUND(100.0 * held_under_500 / NULLIF(legally_innocent, 0), 1)
                                                                AS pct_held_under_500,
        ROUND(100.0 * held_under_1000 / NULLIF(legally_innocent, 0), 1)
                                                                AS pct_held_under_1000,
        ROUND(100.0 * over_6_months_pretrial / NULLIF(legally_innocent, 0), 1)
                                                                AS pct_over_6_months,
        ROUND(100.0 * over_1_year_pretrial / NULLIF(legally_innocent, 0), 1)
                                                                AS pct_over_1_year
    FROM current_population
)
SELECT *
FROM with_rates
ORDER BY pct_legally_innocent DESC;


-- ── Part 2: Innocence by charge category ─────────────────────────────────────
-- Who exactly is being held pretrial?
-- Show that it's predominantly non-violent, poverty-linked, addiction-related.

SELECT
    c.charge_category,
    c.is_violent,
    c.is_poverty_linked,
    c.is_addiction_related,
    fd.jurisdiction,
    COUNT(*)                                                    AS total_pretrial,
    ROUND(AVG(fd.bail_set_amount), 0)                           AS avg_bail_set,
    ROUND(AVG(fd.detention_length_days), 0)                     AS avg_days_detained,
    ROUND(AVG(fd.work_days_to_bail), 1)                         AS avg_work_days_to_bail,
    -- Rank: which charges produce the most pretrial detention?
    RANK() OVER (
        PARTITION BY fd.jurisdiction
        ORDER BY COUNT(*) DESC
    )                                                           AS pretrial_volume_rank
FROM fact_detention fd
JOIN dim_charges c ON fd.primary_charge_key = c.charge_key
WHERE
    fd.pretrial_detention_flag = TRUE
    AND fd.booking_date >= CURRENT_DATE - INTERVAL '1 year'
GROUP BY c.charge_category, c.is_violent, c.is_poverty_linked,
         c.is_addiction_related, fd.jurisdiction
ORDER BY fd.jurisdiction, total_pretrial DESC;


-- ── Part 3: Age breakdown of pretrial population ──────────────────────────────
-- Who is being held legally innocent?
-- Youth (<18) and young adults (18-24) tell a particular story.

SELECT
    i.age_bucket,
    fd.jurisdiction,
    COUNT(*)                                                    AS pretrial_count,
    ROUND(AVG(fd.bail_set_amount), 0)                           AS avg_bail,
    ROUND(AVG(fd.detention_length_days), 0)                     AS avg_days_detained,
    ROUND(100.0 * SUM(CASE WHEN c.is_poverty_linked THEN 1 ELSE 0 END)
          / NULLIF(COUNT(*), 0), 1)                             AS pct_poverty_charges,
    ROUND(100.0 * SUM(CASE WHEN c.is_addiction_related THEN 1 ELSE 0 END)
          / NULLIF(COUNT(*), 0), 1)                             AS pct_addiction_charges
FROM fact_detention fd
JOIN dim_inmate  i ON fd.inmate_key         = i.inmate_key
JOIN dim_charges c ON fd.primary_charge_key = c.charge_key
WHERE
    fd.pretrial_detention_flag = TRUE
    AND fd.booking_date >= CURRENT_DATE - INTERVAL '1 year'
GROUP BY i.age_bucket, fd.jurisdiction
ORDER BY fd.jurisdiction,
    CASE i.age_bucket
        WHEN '<18'   THEN 1
        WHEN '18-24' THEN 2
        WHEN '25-34' THEN 3
        WHEN '35-44' THEN 4
        WHEN '45-54' THEN 5
        WHEN '55-64' THEN 6
        WHEN '65+'   THEN 7
        ELSE 8
    END;
