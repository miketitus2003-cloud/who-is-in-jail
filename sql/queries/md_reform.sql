-- ============================================================
-- QUERY: Maryland Bail Reform — Did It Actually Help?
-- ============================================================
-- On July 1, 2017, Maryland enacted bail reform.
-- Commissioners were now required to consider ability to pay.
-- Cash bail was supposed to be a last resort.
--
-- Did it work?
-- Or did judges just shift from cash bail to remand,
-- keeping the same people locked up through a different mechanism?
--
-- The data has the answer. This query finds it.
-- ============================================================

-- ── Part 1: Before vs. After — top-line comparison ───────────────────────────

WITH md_cohorts AS (
    SELECT
        fd.detention_key,
        fd.booking_date,
        fd.bail_set_amount,
        fd.bail_type,
        fd.bail_paid,
        fd.pretrial_detention_flag,
        fd.detention_length_days,
        fd.work_days_to_bail,
        c.charge_category,
        c.is_violent,
        c.is_poverty_linked,
        c.is_addiction_related,
        g.median_household_income,
        g.zip_code,
        CASE
            WHEN fd.booking_date < '2017-07-01' THEN 'Pre-Reform'
            ELSE 'Post-Reform'
        END                                                     AS reform_period
    FROM fact_detention fd
    JOIN dim_charges   c ON fd.primary_charge_key = c.charge_key
    JOIN dim_geography g ON fd.home_geo_key       = g.geo_key
    WHERE
        fd.jurisdiction = 'MD'
        AND fd.booking_date BETWEEN '2015-07-01' AND '2019-06-30'  -- 2 yrs each side
),
period_stats AS (
    SELECT
        reform_period,
        COUNT(*)                                                AS total_bookings,

        -- Cash bail: set and required to pay
        SUM(CASE WHEN bail_type IN ('Cash', 'Bond') THEN 1 ELSE 0 END)
                                                                AS cash_bail_set,
        ROUND(100.0 * SUM(CASE WHEN bail_type IN ('Cash','Bond') THEN 1 ELSE 0 END)
              / NULLIF(COUNT(*), 0), 1)                         AS pct_cash_bail,

        -- ROR / no cash required
        SUM(CASE WHEN bail_type IN ('ROR', 'No Bail (MD Reform)', 'Supervised Release')
                 THEN 1 ELSE 0 END)                             AS no_cash_required,
        ROUND(100.0 * SUM(CASE WHEN bail_type IN ('ROR','No Bail (MD Reform)','Supervised Release')
                 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 1)  AS pct_no_cash,

        -- Remand: held with NO bail option at all
        -- If remand INCREASED post-reform, the system just shifted mechanisms
        SUM(CASE WHEN bail_type = 'Remand' THEN 1 ELSE 0 END)  AS remand_count,
        ROUND(100.0 * SUM(CASE WHEN bail_type = 'Remand' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(*), 0), 1)                         AS pct_remand,

        -- Pretrial detention overall (regardless of mechanism)
        SUM(CASE WHEN pretrial_detention_flag THEN 1 ELSE 0 END)
                                                                AS pretrial_detained,
        ROUND(100.0 * SUM(CASE WHEN pretrial_detention_flag THEN 1 ELSE 0 END)
              / NULLIF(COUNT(*), 0), 1)                         AS pretrial_rate,

        -- Time in cage
        ROUND(AVG(detention_length_days) FILTER (
            WHERE pretrial_detention_flag
        ), 0)                                                   AS avg_pretrial_days,

        ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY detention_length_days
        ) FILTER (WHERE pretrial_detention_flag), 0)            AS median_pretrial_days,

        -- Bail amounts (when set)
        ROUND(AVG(bail_set_amount) FILTER (WHERE bail_set_amount > 0), 0)
                                                                AS avg_bail_amount,

        -- Poverty-linked charges
        ROUND(100.0 * SUM(CASE WHEN is_poverty_linked THEN 1 ELSE 0 END)
              / NULLIF(COUNT(*), 0), 1)                         AS pct_poverty_charges

    FROM md_cohorts
    GROUP BY reform_period
)
SELECT
    reform_period,
    total_bookings,
    cash_bail_set,
    pct_cash_bail,
    no_cash_required,
    pct_no_cash,
    remand_count,
    pct_remand,
    pretrial_detained,
    pretrial_rate,
    avg_pretrial_days,
    median_pretrial_days,
    avg_bail_amount,
    pct_poverty_charges,
    -- The key question: did total pretrial detention go DOWN?
    -- If pretrial_rate dropped: reform worked.
    -- If remand went up by the same amount: reform was circumvented.
    LAG(pretrial_rate) OVER (ORDER BY reform_period DESC)
                                                                AS comparison_pretrial_rate,
    pretrial_rate - LAG(pretrial_rate) OVER (ORDER BY reform_period DESC)
                                                                AS pretrial_rate_change
FROM period_stats
ORDER BY reform_period;


-- ── Part 2: Monthly trend — where exactly did change happen? ─────────────────

WITH monthly AS (
    SELECT
        DATE_TRUNC('month', fd.booking_date)                    AS booking_month,
        COUNT(*)                                                AS bookings,
        SUM(CASE WHEN fd.bail_type IN ('Cash','Bond') THEN 1 ELSE 0 END)
                                                                AS cash_bail,
        SUM(CASE WHEN fd.bail_type IN ('ROR','No Bail (MD Reform)','Supervised Release')
                 THEN 1 ELSE 0 END)                             AS no_cash_bail,
        SUM(CASE WHEN fd.bail_type = 'Remand' THEN 1 ELSE 0 END)
                                                                AS remand,
        SUM(CASE WHEN fd.pretrial_detention_flag THEN 1 ELSE 0 END)
                                                                AS pretrial_detained,
        ROUND(AVG(fd.detention_length_days) FILTER (
            WHERE fd.pretrial_detention_flag
        ), 0)                                                   AS avg_pretrial_days
    FROM fact_detention fd
    WHERE
        fd.jurisdiction = 'MD'
        AND fd.booking_date BETWEEN '2015-07-01' AND '2019-06-30'
    GROUP BY 1
)
SELECT
    booking_month,
    bookings,
    cash_bail,
    no_cash_bail,
    remand,
    pretrial_detained,
    ROUND(100.0 * pretrial_detained / NULLIF(bookings, 0), 1)  AS pretrial_rate,
    avg_pretrial_days,
    -- Reform line
    CASE WHEN booking_month >= '2017-07-01' THEN 'Post-Reform' ELSE 'Pre-Reform' END
                                                                AS period,
    -- 3-month rolling average of pretrial rate (smooth out noise)
    ROUND(AVG(100.0 * pretrial_detained / NULLIF(bookings, 0)) OVER (
        ORDER BY booking_month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 1)                                                       AS rolling_pretrial_rate,
    -- Month-over-month change
    pretrial_detained - LAG(pretrial_detained, 1) OVER (ORDER BY booking_month)
                                                                AS pretrial_change_mom,
    -- Year-over-year change
    ROUND(100.0 * (pretrial_detained - LAG(pretrial_detained, 12) OVER (ORDER BY booking_month))
          / NULLIF(LAG(pretrial_detained, 12) OVER (ORDER BY booking_month), 0), 1)
                                                                AS pretrial_change_yoy_pct,
    -- Cumulative no-cash-bail post reform
    SUM(no_cash_bail) OVER (
        ORDER BY booking_month
        ROWS UNBOUNDED PRECEDING
    )                                                           AS cumulative_no_cash_bail
FROM monthly
ORDER BY booking_month;


-- ── Part 3: Reform impact by income level ────────────────────────────────────
-- Did reform help everyone equally — or only certain income groups?
-- If the poorest ZIPs saw no improvement, reform failed the people who needed it most.

SELECT
    CASE
        WHEN g.median_household_income < 35000  THEN '1: Under $35k'
        WHEN g.median_household_income < 55000  THEN '2: $35k-$55k'
        WHEN g.median_household_income < 80000  THEN '3: $55k-$80k'
        ELSE                                         '4: Over $80k'
    END                                                         AS income_tier,
    CASE WHEN fd.booking_date < '2017-07-01' THEN 'Pre-Reform' ELSE 'Post-Reform' END
                                                                AS period,
    COUNT(*)                                                    AS bookings,
    ROUND(100.0 * SUM(CASE WHEN fd.pretrial_detention_flag THEN 1 ELSE 0 END)
          / NULLIF(COUNT(*), 0), 1)                             AS pretrial_rate,
    ROUND(100.0 * SUM(CASE WHEN fd.bail_type = 'Remand' THEN 1 ELSE 0 END)
          / NULLIF(COUNT(*), 0), 1)                             AS remand_rate,
    ROUND(AVG(fd.detention_length_days) FILTER (
        WHERE fd.pretrial_detention_flag
    ), 0)                                                       AS avg_pretrial_days,
    ROUND(AVG(fd.bail_set_amount) FILTER (WHERE fd.bail_set_amount > 0), 0)
                                                                AS avg_bail_set
FROM fact_detention fd
JOIN dim_geography g ON fd.home_geo_key = g.geo_key
WHERE
    fd.jurisdiction = 'MD'
    AND fd.booking_date BETWEEN '2015-07-01' AND '2019-06-30'
GROUP BY income_tier, period
ORDER BY income_tier, period;
