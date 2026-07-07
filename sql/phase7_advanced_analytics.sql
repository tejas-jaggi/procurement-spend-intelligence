-- ============================================================
-- PROCUREMENT SPEND INTELLIGENCE PLATFORM
-- ============================================================
-- File:    phase7_advanced_analytics.sql
-- Purpose: 
-- Demonstrate advanced SQL techniques commonly used by
-- Data Analysts, Business Analysts, Procurement Analysts,
-- and Analytics Engineers to solve complex business problems.
-- DB:      DuckDB 1.5.x
-- This phase extends the business analytics developed in
-- Phase 6 by introducing window functions, ranking,
-- cumulative analysis, Pareto analysis, reusable views,
-- and executive KPI reporting.
-- ============================================================
-- New SQL Concepts in This File:
--
--   RANK()        → ranks rows, leaves gaps when values tie (1,1,3)
--   DENSE_RANK()  → ranks rows, no gaps on ties (1,1,2)
--   ROW_NUMBER()  → unique sequential number regardless of ties
--   LAG()         → retrieves a value from N rows earlier
--   SUM() OVER()  → running / cumulative total without GROUP BY
--   AVG() OVER()  → rolling average over a sliding window
--   PARTITION BY  → resets the window function per group
--   ROWS BETWEEN  → defines the window frame size
--   CREATE VIEW   → saves a query as a reusable virtual table

-- Execute after:
--   1. schema.sql
--   2. data_generation.sql
--   3. validation.sql
--   4. spend_analysis.sql
-- ============================================================

-- ============================================================
-- SECTION 1: RANK vs DENSE_RANK vs ROW_NUMBER
-- ============================================================
-- These three functions all number rows but behave differently
-- when two suppliers have the same spend value (a tie):
--
--   RANK()       → 1st, 1st, 3rd   (gap after tie)
--   DENSE_RANK() → 1st, 1st, 2nd   (no gap after tie)
--   ROW_NUMBER() → 1st, 2nd, 3rd   (always unique, tie broken arbitrarily)
--
-- Business Use: Supplier spend ranking. Who is #1, #2, #3?
-- What happens when two suppliers spend nearly the same amount?
-- ============================================================

WITH supplier_spend AS (
    SELECT
        s.supplier_name,
        s.supplier_code,
        s.supplier_tier,
        SUM(f.total_amount) AS total_spend
    FROM fact_purchase_orders f
    JOIN dim_suppliers s ON f.supplier_id = s.supplier_id
    WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
    GROUP BY s.supplier_name, s.supplier_code, s.supplier_tier
)
SELECT
    supplier_name,
    supplier_tier,
    ROUND(total_spend / 1000000.0, 2)              AS spend_millions,
    RANK()       OVER (ORDER BY total_spend DESC)   AS rank_with_gaps,
    DENSE_RANK() OVER (ORDER BY total_spend DESC)   AS dense_rank,
    ROW_NUMBER() OVER (ORDER BY total_spend DESC)   AS row_num
FROM supplier_spend
ORDER BY total_spend DESC;

-- Expected: For most rows rank_with_gaps = dense_rank = row_num.
-- They diverge only when two suppliers have identical spend.
-- In analyst interviews, DENSE_RANK is preferred for "Top N" reports.


-- ============================================================
-- SECTION 2: RANK WITHIN GROUP — PARTITION BY
-- ============================================================
-- PARTITION BY resets the window function for each group.
-- Think of it as GROUP BY for window functions — it splits the
-- data into partitions but keeps all rows visible.
--
-- Business Use: Who is the top supplier WITHIN each tier?
-- Useful for rationalizing the supply base:
-- "Which Approved supplier should be promoted to Preferred?"
-- ============================================================

WITH supplier_spend AS (
    SELECT
        s.supplier_name,
        s.supplier_code,
        s.supplier_tier,
        SUM(f.total_amount) AS total_spend,
        SUM(SUM(f.total_amount)) OVER ()  AS grand_total
    FROM fact_purchase_orders f
    JOIN dim_suppliers s ON f.supplier_id = s.supplier_id
    WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
    GROUP BY s.supplier_name, s.supplier_code, s.supplier_tier
)
SELECT
    supplier_tier,
    supplier_name,
    supplier_code,
    ROUND(total_spend / 1000000.0, 2)                                        AS spend_millions,
    ROUND(total_spend * 100.0 / grand_total, 1)                              AS supplier_spend_pct,
    -- Rank within each tier: resets to 1 for each new tier
    DENSE_RANK() OVER (PARTITION BY supplier_tier ORDER BY total_spend DESC) AS rank_within_tier,
    -- Rank across all 30 suppliers: never resets
    DENSE_RANK() OVER (ORDER BY total_spend DESC)                            AS overall_rank
FROM supplier_spend
ORDER BY supplier_tier, rank_within_tier;

-- Expected: Each tier shows its own #1, #2, #3... supplier.
-- The Approved supplier ranked #1 within tier but overall_rank > 16
-- is a candidate for promotion to Preferred.


-- ============================================================
-- SECTION 3: LAG() — YEAR-OVER-YEAR MONTHLY GROWTH
-- ============================================================
-- LAG(column, offset) returns the value from 'offset' rows
-- earlier in the result set, based on the ORDER BY clause.
--
-- LAG(spend, 12) at row 13 (Jan 2023) returns the value from
-- row 1 (Jan 2022) — same month, one year earlier.
--
-- Business Use: Is this month's spend higher or lower than
-- the same month last year?
-- ============================================================

WITH monthly_spend AS (
    SELECT
        d.year,
        d.month,
        d.month_label,
        ROUND(SUM(f.total_amount) / 1000000.0, 3) AS spend_millions
    FROM fact_purchase_orders f
    JOIN dim_date d ON f.date_id = d.date_id
    WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
    GROUP BY d.year, d.month, d.month_label
)
SELECT
    year,
    month,
    month_label,
    spend_millions,
    -- LAG(x, 12): same month from the prior year
    LAG(spend_millions, 12) OVER (ORDER BY year, month)                           AS prior_year_spend,
    ROUND(
        spend_millions - LAG(spend_millions, 12) OVER (ORDER BY year, month)
    , 3)                                                                           AS yoy_change_millions,
    ROUND(
        (spend_millions - LAG(spend_millions, 12) OVER (ORDER BY year, month))
        * 100.0
        / NULLIF(LAG(spend_millions, 12) OVER (ORDER BY year, month), 0)
    , 1)                                                                           AS yoy_growth_pct
FROM monthly_spend
ORDER BY year, month;

-- Expected: Jan-Dec 2022 shows NULL for prior_year_spend (no prior year).
-- 2023 and 2024 rows show year-over-year comparison.
-- Positive yoy_growth_pct = procurement increasing.
-- The NULLIF prevents division-by-zero if a month had zero spend.


-- ============================================================
-- SECTION 4: RUNNING TOTALS — SUM() OVER (ORDER BY ...)
-- ============================================================
-- Adding ORDER BY inside SUM() OVER() creates a running total
-- that accumulates row by row.
--
-- ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW means:
-- "sum everything from the first row up to this row."
--
-- PARTITION BY year resets the running total each January.
--
-- Business Use: How much has AMG spent in total through each
-- month of the year? (Year-to-Date spend tracker)
-- ============================================================

WITH monthly AS (
    SELECT
        d.year,
        d.month,
        d.month_label,
        d.quarter_label,
        SUM(f.total_amount) AS monthly_spend
    FROM fact_purchase_orders f
    JOIN dim_date d ON f.date_id = d.date_id
    WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
    GROUP BY d.year, d.month, d.month_label, d.quarter_label
)
SELECT
    year,
    month_label,
    quarter_label,
    ROUND(monthly_spend / 1000000.0, 2)                               AS monthly_spend_millions,
    -- YTD spend: resets each January (PARTITION BY year)
    ROUND(SUM(monthly_spend) OVER (
        PARTITION BY year
        ORDER BY month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) / 1000000.0, 2)                                                 AS ytd_spend_millions,
    -- Cumulative all-time spend: never resets
    ROUND(SUM(monthly_spend) OVER (
        ORDER BY year, month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) / 1000000.0, 2)                                                 AS lifetime_cumulative_spend
FROM monthly
ORDER BY year, month;

-- Expected: ytd_spend_millions resets to ~$X in January each year.
-- By December it matches the annual total from Section 1 of Phase 6.
-- lifetime_cumulative_spend reaches $256M+ by Dec 2024.


-- ============================================================
-- SECTION 5: SUPPLIER PARETO ANALYSIS — THE 80/20 RULE
-- ============================================================
-- The Pareto Principle states that 80% of consequences come
-- from 20% of causes. In procurement:
--   80% of spend comes from 20% of suppliers.
--
-- This is one of the most cited analyses in procurement.
-- Executives use it to decide where to focus negotiation
-- effort, supplier development, and risk management.
--
-- SQL technique: RANK() + SUM() OVER() + cumulative % threshold
-- ============================================================

WITH
supplier_spend AS (
    SELECT
        s.supplier_id,
        s.supplier_name,
        s.supplier_code,
        s.supplier_tier,
        s.region,
        SUM(f.total_amount) AS total_spend
    FROM fact_purchase_orders f
    JOIN dim_suppliers s ON f.supplier_id = s.supplier_id
    WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
    GROUP BY s.supplier_id, s.supplier_name, s.supplier_code, s.supplier_tier, s.region
),
pareto AS (
    SELECT
        supplier_name,
        supplier_code,
        supplier_tier,
        region,
        total_spend,
        DENSE_RANK() OVER (ORDER BY total_spend DESC)                            AS spend_rank,
        -- Running spend total (largest supplier first)
        SUM(total_spend) OVER (
            ORDER BY total_spend DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )                                                                         AS cumulative_spend,
        -- Grand total for percentage calculations
        SUM(total_spend) OVER ()                                                  AS grand_total
    FROM supplier_spend
)
SELECT
    spend_rank,
    supplier_name,
    supplier_code,
    supplier_tier,
    ROUND(total_spend / 1000000.0, 2)                    AS spend_millions,
    ROUND(total_spend * 100.0 / grand_total, 1)          AS pct_of_total,
    ROUND(cumulative_spend / 1000000.0, 2)               AS cumulative_millions,
    ROUND(cumulative_spend * 100.0 / grand_total, 1)     AS cumulative_pct,
    CASE
        WHEN cumulative_spend * 100.0 / grand_total <= 80
        THEN 'VITAL FEW  — Priority management'
        ELSE 'USEFUL MANY — Standard management'
    END                                                   AS pareto_group
FROM pareto
ORDER BY spend_rank;

-- Expected:
-- Count the rows labeled 'VITAL FEW'.
-- If 6 out of 30 suppliers are in the VITAL FEW group,
-- then 20% of suppliers control 80% of spend. Classic 80/20.
-- Any Approved or Spot supplier in the VITAL FEW group is a
-- concentration risk — too much spend with a low-tier vendor.


-- ============================================================
-- SECTION 6: CATEGORY PARETO ANALYSIS
-- ============================================================
-- Same technique applied to spend categories.
-- Business Use: Which categories should receive the most
-- procurement negotiation and cost reduction focus?
-- ============================================================

WITH
cat_spend AS (
    SELECT
        c.category_name,
        c.category_group,
        c.category_code,
        SUM(f.total_amount) AS total_spend
    FROM fact_purchase_orders f
    JOIN dim_categories c ON f.category_id = c.category_id
    WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
    GROUP BY c.category_name, c.category_group, c.category_code
)
SELECT
    DENSE_RANK() OVER (ORDER BY total_spend DESC)                          AS category_rank,
    category_name,
    category_group,
    category_code,
    ROUND(total_spend / 1000000.0, 2)                                     AS spend_millions,
    ROUND(total_spend * 100.0 / SUM(total_spend) OVER (), 1)              AS pct_of_total,
    ROUND(SUM(total_spend) OVER (
        ORDER BY total_spend DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) * 100.0 / SUM(total_spend) OVER (), 1)                              AS cumulative_pct,
    CASE
        WHEN SUM(total_spend) OVER (
            ORDER BY total_spend DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) * 100.0 / SUM(total_spend) OVER () <= 80
        THEN 'PRIORITY — Strategic sourcing focus'
        ELSE 'STANDARD — Monitor only'
    END                                                                    AS priority_group
FROM cat_spend
ORDER BY category_rank;

-- The analysis evaluates whether supplier spend is concentrated. The exact percentage of suppliers required to reach 80% of spend depends on the organization's procurement profile.
-- Direct categories (Raw Materials, Components) should dominate.
-- These are where price negotiation and strategic sourcing
-- will yield the highest procurement savings.


-- ============================================================
-- SECTION 7: 3-MONTH ROLLING AVERAGE — SUPPLIER OTD TREND
-- ============================================================
-- A rolling average smooths monthly noise so the underlying
-- trend becomes visible.
--
-- ROWS BETWEEN 2 PRECEDING AND CURRENT ROW means:
-- "average this row and the two rows before it."
-- At row 3: average of rows 1, 2, 3.
-- At row 4: average of rows 2, 3, 4. (the window slides forward)
--
-- Business Use: Is supplier on-time delivery truly declining,
-- or are single bad months creating false alarms?
-- Applied to the three deteriorating suppliers from Phase 5.
-- ============================================================

SELECT
    s.supplier_name,
    d.month_label,
    d.year,
    d.month,
    p.on_time_delivery_rate                                              AS monthly_otd,
    -- 3-month rolling average (smooths short-term noise)
    ROUND(AVG(p.on_time_delivery_rate) OVER (
        PARTITION BY p.supplier_id
        ORDER BY p.date_id
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 1)                                                                AS otd_3mo_rolling_avg,
    -- 6-month rolling average (reveals the longer-term trend)
    ROUND(AVG(p.on_time_delivery_rate) OVER (
        PARTITION BY p.supplier_id
        ORDER BY p.date_id
        ROWS BETWEEN 5 PRECEDING AND CURRENT ROW
    ), 1)                                                                AS otd_6mo_rolling_avg
FROM fact_supplier_performance p
JOIN dim_suppliers s ON p.supplier_id = s.supplier_id
JOIN dim_date      d ON p.date_id     = d.date_id
WHERE s.supplier_id IN (20, 24, 26)
ORDER BY p.supplier_id, p.date_id;

-- Expected: ProFreight (26) shows a clearly declining 6-month rolling avg.
-- ToolMaster (20) and Summit Chemical (24) show modest decline.
-- The rolling avg makes the structural decline visible even through
-- monthly fluctuations. This is evidence for a Supplier Corrective
-- Action Request (SCAR) in a real procurement context.


-- ============================================================
-- SECTION 8: COMPOSITE SUPPLIER RISK MODEL
-- ============================================================
-- A single risk score per supplier that combines 4 dimensions:
--   30% — Average risk score (from performance table)
--   30% — Late delivery rate (from actual PO transactions)
--   20% — Average defect rate (from performance table)
--   20% — OTD trend (first vs last observation — Phase 5 method)
-- The weighting emphasizes operational reliability (late deliveries and risk score) because these factors have the greatest impact on procurement continuity. Defects and performance trend provide additional context without dominating the index.
-- The Phase 5 lesson is embedded here: OTD trend uses each
-- supplier's own FIRST and LAST data points, not fixed periods.
-- ============================================================

WITH
-- Input 1: Transaction-based stats from purchase orders
po_stats AS (
    SELECT
        f.supplier_id,
        COUNT(f.po_id)                                                      AS po_count,
        SUM(f.total_amount)                                                 AS total_spend,
        ROUND(COUNT(CASE WHEN f.days_late > 0 THEN 1 END) * 100.0
              / NULLIF(COUNT(CASE WHEN f.days_late IS NOT NULL THEN 1 END), 0), 1) AS late_pct
    FROM fact_purchase_orders f
    WHERE f.po_status IN ('Closed', 'Approved')
    GROUP BY f.supplier_id
),
-- Input 2: KPI averages from performance table
perf_stats AS (
    SELECT
        supplier_id,
        ROUND(AVG(risk_score), 2)            AS avg_risk,
        ROUND(AVG(defect_rate), 2)           AS avg_defect,
        ROUND(AVG(on_time_delivery_rate), 1) AS avg_otd
    FROM fact_supplier_performance
    GROUP BY supplier_id
),
-- Input 3: OTD trend — first vs last available observation
-- (applying the Phase 5/6 lesson; no fixed calendar periods)
otd_bounds AS (
    SELECT supplier_id, MIN(date_id) AS first_dt, MAX(date_id) AS last_dt
    FROM fact_supplier_performance
    GROUP BY supplier_id
),
otd_trend AS (
    SELECT
        b.supplier_id,
        f.on_time_delivery_rate AS first_otd,
        l.on_time_delivery_rate AS last_otd,
        l.on_time_delivery_rate - f.on_time_delivery_rate AS otd_change
    FROM otd_bounds b
    JOIN fact_supplier_performance f ON b.supplier_id = f.supplier_id AND b.first_dt = f.date_id
    JOIN fact_supplier_performance l ON b.supplier_id = l.supplier_id AND b.last_dt  = l.date_id
),
-- Composite score assembly
scored AS (
    SELECT
        p.supplier_id,
        p.po_count,
        p.total_spend,
        p.late_pct,
        ps.avg_risk,
        ps.avg_defect,
        ps.avg_otd,
        ot.first_otd,
        ot.last_otd,
        ot.otd_change,
        ROUND(
            (ps.avg_risk * 0.30)
            + (LEAST(p.late_pct / 10.0, 10.0) * 0.30)
            + (LEAST(ps.avg_defect, 10.0) * 0.20)
            + (CASE
                WHEN ot.otd_change <= -10 THEN 2.0
                WHEN ot.otd_change <=  -5 THEN 1.0
                WHEN ot.otd_change <=  -2 THEN 0.5
                ELSE                           0.0
               END * 0.20)
        , 2) AS composite_risk
    FROM po_stats p
    JOIN perf_stats ps ON p.supplier_id = ps.supplier_id
    JOIN otd_trend  ot ON p.supplier_id = ot.supplier_id
)
SELECT
    s.supplier_name,
    s.supplier_code,
    s.supplier_tier,
    sc.po_count,
    ROUND(sc.total_spend / 1000000.0, 2)          AS spend_millions,
    sc.late_pct                                    AS late_delivery_pct,
    sc.avg_risk                                    AS avg_risk_score,
    sc.avg_defect                                  AS avg_defect_pct,
    ROUND(sc.otd_change, 1)                        AS otd_trend_change_pp,
    sc.composite_risk                              AS supplier_risk_index,
    CASE
        WHEN sc.composite_risk >= 6.0 THEN 'CRITICAL'
        WHEN sc.composite_risk >= 4.0 THEN 'HIGH'
        WHEN sc.composite_risk >= 2.5 THEN 'MEDIUM'
        ELSE                               'LOW'
    END                                            AS risk_tier,
    CASE
        WHEN sc.total_spend > 5000000 AND sc.composite_risk >= 4.0 THEN 'IMMEDIATE ACTION'
        WHEN sc.total_spend > 2000000 AND sc.composite_risk >= 2.5 THEN 'MONITOR CLOSELY'
        ELSE                                                              'ROUTINE REVIEW'
    END                                            AS action_required
FROM scored sc
JOIN dim_suppliers s ON sc.supplier_id = s.supplier_id
ORDER BY sc.composite_risk DESC, sc.total_spend DESC;

-- Expected:
-- Delta Equipment (SUP-030) likely appears near the top — high late_pct.
-- Suppliers 20, 24, 26 appear elevated due to negative otd_trend.
-- IMMEDIATE ACTION = the most dangerous combination of spend and risk.
-- These are the suppliers a CPO prioritizes for executive review.


-- ============================================================
-- SECTION 9: EXECUTIVE PROCUREMENT KPI DASHBOARD
-- ============================================================
-- Business Objective:
-- Consolidate key procurement performance metrics into a
-- single executive-level view suitable for dashboarding.
--
-- These KPIs provide leadership with a high-level summary
-- of procurement efficiency, supplier performance, and
-- overall purchasing activity.
-- ============================================================

WITH
volume AS (
    SELECT
        SUM(total_amount)           AS total_spend,
        COUNT(*)                    AS total_pos,
        COUNT(DISTINCT supplier_id) AS active_suppliers,
        AVG(total_amount)           AS avg_po_value
    FROM fact_purchase_orders
    WHERE po_status NOT IN ('Rejected', 'Cancelled')
),
kpis AS (
    SELECT
        ROUND(AVG(on_time_delivery_rate), 1)          AS avg_otd_pct,
        ROUND(AVG(defect_rate), 2)                    AS avg_defect_pct,
        ROUND(AVG(avg_lead_time_days), 1)             AS avg_lead_days,
        COUNT(CASE WHEN risk_score >= 7 THEN 1 END)   AS high_risk_supplier_assessments
    FROM fact_supplier_performance
),
payments AS (
    SELECT
        SUM(CASE WHEN payment_status = 'Overdue'  THEN total_amount ELSE 0 END) AS overdue_spend,
        SUM(CASE WHEN payment_status = 'Disputed' THEN total_amount ELSE 0 END) AS disputed_spend
    FROM fact_purchase_orders
    WHERE po_status NOT IN ('Rejected', 'Cancelled')
),
strategic_pct AS (
    SELECT
        ROUND(SUM(f.total_amount) * 100.0
              / (SELECT SUM(total_amount) FROM fact_purchase_orders
                 WHERE po_status NOT IN ('Rejected','Cancelled')), 1) AS pct
    FROM fact_purchase_orders f
    JOIN dim_suppliers s ON f.supplier_id = s.supplier_id
    WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
      AND s.supplier_tier = 'Strategic'
)
SELECT
    ROUND(v.total_spend / 1000000.0, 2)   AS total_spend_millions,
    v.total_pos                            AS total_purchase_orders,
    v.active_suppliers,
    ROUND(v.avg_po_value, 0)               AS avg_po_value_usd,
    sp.pct                                 AS strategic_spend_pct,
    k.avg_otd_pct,
    k.avg_defect_pct,
    k.avg_lead_days,
    k.high_risk_supplier_assessments,
    ROUND(p.overdue_spend  / 1000000.0, 2) AS overdue_millions,
    ROUND(p.disputed_spend / 1000000.0, 2) AS disputed_millions
FROM volume v, kpis k, payments p, strategic_pct sp;


-- ============================================================
-- SECTION 10: SAVINGS OPPORTUNITY ANALYSIS
-- Business Use:
-- Identify the procurement actions likely to generate the
-- greatest financial impact. Recommendations are prioritized
-- using supplier spend, operational performance, and sourcing
-- characteristics rather than spend alone.
-- Three lenses: renegotiation, spot consolidation, escalation.
-- ============================================================

-- 10A: High-spend + poor-performance = renegotiation targets
WITH spend_late AS (
    SELECT
        s.supplier_name,
        s.supplier_tier,
        s.supplier_code,
        SUM(f.total_amount) AS total_spend,
        ROUND(COUNT(CASE WHEN f.days_late > 0 THEN 1 END) * 100.0
              / NULLIF(COUNT(CASE WHEN f.days_late IS NOT NULL THEN 1 END), 0), 1) AS late_pct
    FROM fact_purchase_orders f
    JOIN dim_suppliers s ON f.supplier_id = s.supplier_id
    WHERE f.po_status IN ('Closed', 'Approved')
    GROUP BY s.supplier_name, s.supplier_tier, s.supplier_code
),
grand AS (SELECT SUM(total_spend) AS total FROM spend_late)
SELECT
    sl.supplier_name,
    sl.supplier_tier,
    ROUND(sl.total_spend / 1000000.0, 2)              AS spend_millions,
    ROUND(sl.total_spend * 100.0 / g.total, 1)        AS pct_of_spend,
    sl.late_pct                                        AS late_delivery_pct,
    CASE
        WHEN sl.total_spend > 5000000 AND sl.late_pct > 25 THEN 'HIGH — Renegotiate with SLA penalties'
        WHEN sl.total_spend > 2000000 AND sl.late_pct > 30 THEN 'MEDIUM — Issue supplier improvement plan'
        WHEN sl.late_pct > 40                              THEN 'MEDIUM — Review relationship continuation'
        ELSE                                                    'LOW — Routine management'
    END AS recommended_action
FROM spend_late sl
CROSS JOIN grand g
WHERE sl.total_spend > 1000000
ORDER BY sl.total_spend DESC;

-- 10B: Spot supplier spend — consolidation opportunity
-- Spot purchases are unplanned and usually cost more per unit.
-- Moving Spot spend to Preferred suppliers saves money.
SELECT
    s.supplier_name,
    s.supplier_code,
    COUNT(f.po_id)                              AS po_count,
    ROUND(SUM(f.total_amount) / 1000000.0, 2)  AS spend_millions,
    ROUND(AVG(f.total_amount), 0)               AS avg_po_value,
    'Consolidate into Preferred/Approved contract' AS recommendation
FROM fact_purchase_orders f
JOIN dim_suppliers s ON f.supplier_id = s.supplier_id
WHERE s.supplier_tier = 'Spot'
  AND f.po_status NOT IN ('Rejected', 'Cancelled')
GROUP BY s.supplier_name, s.supplier_code
ORDER BY spend_millions DESC;

-- 10C: Category cost escalation — where is inflation hitting?
WITH yoy AS (
    SELECT
        c.category_name,
        c.category_group,
        SUM(CASE WHEN d.year = 2022 THEN f.total_amount ELSE 0 END) AS y2022,
        SUM(CASE WHEN d.year = 2023 THEN f.total_amount ELSE 0 END) AS y2023,
        SUM(CASE WHEN d.year = 2024 THEN f.total_amount ELSE 0 END) AS y2024
    FROM fact_purchase_orders f
    JOIN dim_date d       ON f.date_id     = d.date_id
    JOIN dim_categories c ON f.category_id = c.category_id
    WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
    GROUP BY c.category_name, c.category_group
)
SELECT
    category_name,
    category_group,
    ROUND(y2022 / 1000000.0, 2)                                    AS spend_2022m,
    ROUND(y2023 / 1000000.0, 2)                                    AS spend_2023m,
    ROUND(y2024 / 1000000.0, 2)                                    AS spend_2024m,
    ROUND((y2023 - y2022) * 100.0 / NULLIF(y2022, 0), 1)          AS growth_22_23_pct,
    ROUND((y2024 - y2023) * 100.0 / NULLIF(y2023, 0), 1)          AS growth_23_24_pct,
    CASE
        WHEN (y2024 - y2023) * 100.0 / NULLIF(y2023, 0) > 10 THEN 'ESCALATING — Investigate pricing'
        WHEN (y2024 - y2023) * 100.0 / NULLIF(y2023, 0) < -10 THEN 'DECLINING — Monitor volumes'
        ELSE 'STABLE'
    END AS escalation_flag
FROM yoy
ORDER BY y2024 DESC;


-- ============================================================
-- SECTION 11: CREATE REUSABLE VIEWS
-- ============================================================
-- A VIEW saves a SELECT query in the database.
-- Querying a view is identical to querying a table.
-- Benefits:
--   Reusable  — write the JOIN once, query it everywhere
--   Readable  — business-friendly name hides complexity
--   Consistent — all teams use the same logic
-- ============================================================

-- View 1: Supplier Scorecard
-- One row per supplier combining PO stats + performance KPIs.
-- Use this whenever you need a full supplier picture.
CREATE OR REPLACE VIEW v_supplier_scorecard AS
WITH po_stats AS (
    SELECT
        f.supplier_id,
        COUNT(f.po_id)                                                            AS total_pos,
        ROUND(SUM(f.total_amount) / 1000000.0, 2)                                AS spend_millions,
        ROUND(AVG(f.total_amount), 0)                                             AS avg_po_value,
        ROUND(COUNT(CASE WHEN f.days_late > 0 THEN 1 END) * 100.0
              / NULLIF(COUNT(CASE WHEN f.days_late IS NOT NULL THEN 1 END), 0), 1) AS late_delivery_pct,
        ROUND(COUNT(CASE WHEN f.payment_status = 'Overdue' THEN 1 END) * 100.0
              / NULLIF(COUNT(f.po_id), 0), 1)                                     AS overdue_invoice_pct
    FROM fact_purchase_orders f
    WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
    GROUP BY f.supplier_id
),
perf_stats AS (
    SELECT
        supplier_id,
        ROUND(AVG(on_time_delivery_rate), 1) AS avg_otd_pct,
        ROUND(AVG(defect_rate), 2)           AS avg_defect_pct,
        ROUND(AVG(risk_score), 1)            AS avg_risk_score,
        ROUND(AVG(performance_score), 1)     AS avg_perf_score,
        ROUND(AVG(avg_lead_time_days), 1)    AS avg_lead_days
    FROM fact_supplier_performance
    GROUP BY supplier_id
)
SELECT
    s.supplier_id,
    s.supplier_name,
    s.supplier_code,
    s.supplier_tier,
    s.region,
    s.payment_terms,
    p.total_pos,
    p.spend_millions,
    p.avg_po_value,
    p.late_delivery_pct,
    p.overdue_invoice_pct,
    ps.avg_otd_pct,
    ps.avg_defect_pct,
    ps.avg_risk_score,
    ps.avg_perf_score,
    ps.avg_lead_days,
    CASE
        WHEN ps.avg_risk_score >= 6   THEN 'CRITICAL'
        WHEN ps.avg_risk_score >= 4   THEN 'HIGH RISK'
        WHEN ps.avg_risk_score >= 2.5 THEN 'MEDIUM RISK'
        ELSE                               'LOW RISK'
    END AS risk_category
FROM dim_suppliers s
LEFT JOIN po_stats   p  ON s.supplier_id = p.supplier_id
LEFT JOIN perf_stats ps ON s.supplier_id = ps.supplier_id;

-- Usage examples:
-- SELECT * FROM v_supplier_scorecard ORDER BY spend_millions DESC;
-- SELECT * FROM v_supplier_scorecard WHERE risk_category = 'CRITICAL';
-- SELECT * FROM v_supplier_scorecard WHERE supplier_tier = 'Strategic';


-- View 2: Supplier Pareto (always-current 80/20 analysis)
CREATE OR REPLACE VIEW v_supplier_pareto AS
WITH ss AS (
    SELECT
        s.supplier_id,
        s.supplier_name,
        s.supplier_code,
        s.supplier_tier,
        SUM(f.total_amount) AS total_spend
    FROM fact_purchase_orders f
    JOIN dim_suppliers s ON f.supplier_id = s.supplier_id
    WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
    GROUP BY s.supplier_id, s.supplier_name, s.supplier_code, s.supplier_tier
)
SELECT
    DENSE_RANK() OVER (ORDER BY total_spend DESC)              AS spend_rank,
    supplier_name,
    supplier_code,
    supplier_tier,
    ROUND(total_spend / 1000000.0, 2)                         AS spend_millions,
    ROUND(total_spend * 100.0 / SUM(total_spend) OVER (), 1)  AS pct_of_spend,
    ROUND(SUM(total_spend) OVER (
        ORDER BY total_spend DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) * 100.0 / SUM(total_spend) OVER (), 1)                  AS cumulative_pct,
    CASE
        WHEN SUM(total_spend) OVER (
            ORDER BY total_spend DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) * 100.0 / SUM(total_spend) OVER () <= 80
        THEN 'VITAL FEW'
        ELSE 'USEFUL MANY'
    END AS pareto_group
FROM ss
ORDER BY spend_rank;

-- Usage examples:
-- SELECT * FROM v_supplier_pareto WHERE pareto_group = 'VITAL FEW';
-- SELECT COUNT(*) FROM v_supplier_pareto WHERE pareto_group = 'VITAL FEW';


-- View 3: Executive KPI Dashboard (one-row summary)
CREATE OR REPLACE VIEW v_executive_kpi AS
SELECT
    ROUND((SELECT SUM(total_amount) FROM fact_purchase_orders
           WHERE po_status NOT IN ('Rejected','Cancelled')) / 1000000.0, 2)       AS total_spend_millions,
    (SELECT COUNT(*) FROM fact_purchase_orders
     WHERE po_status NOT IN ('Rejected','Cancelled'))                              AS active_po_count,
    (SELECT COUNT(DISTINCT supplier_id) FROM fact_purchase_orders
     WHERE po_status NOT IN ('Rejected','Cancelled'))                              AS active_suppliers,
    (SELECT ROUND(AVG(on_time_delivery_rate), 1) FROM fact_supplier_performance)   AS avg_otd_pct,
    (SELECT ROUND(AVG(defect_rate), 2) FROM fact_supplier_performance)             AS avg_defect_pct,
    (SELECT ROUND(AVG(risk_score), 1) FROM fact_supplier_performance)              AS avg_risk_score,
    (SELECT COUNT(CASE WHEN risk_score >= 7 THEN 1 END)
     FROM fact_supplier_performance)                                               AS high_risk_records,
    (SELECT ROUND(SUM(CASE WHEN payment_status = 'Overdue' THEN total_amount ELSE 0 END) / 1000000.0, 2)
     FROM fact_purchase_orders
     WHERE po_status NOT IN ('Rejected','Cancelled'))                              AS overdue_millions,
    (SELECT ROUND(SUM(CASE WHEN payment_status = 'Disputed' THEN total_amount ELSE 0 END) / 1000000.0, 2)
     FROM fact_purchase_orders
     WHERE po_status NOT IN ('Rejected','Cancelled'))                              AS disputed_millions;

-- Usage: SELECT * FROM v_executive_kpi;


-- ============================================================
-- VERIFY VIEWS WERE CREATED
-- ============================================================
SELECT table_name AS view_name
FROM information_schema.tables
WHERE table_type = 'VIEW'
ORDER BY table_name;

-- Expected:
--   v_executive_kpi
--   v_supplier_pareto
--   v_supplier_scorecard

-- ============================================================
-- ADVANCED SQL SKILLS DEMONSTRATED
--
-- ✓ Window Functions
-- ✓ Ranking Functions
-- ✓ PARTITION BY
-- ✓ Common Table Expressions (CTEs)
-- ✓ Running Totals
-- ✓ Rolling Averages
-- ✓ Pareto Analysis
-- ✓ Composite Risk Scoring
-- ✓ Executive KPI Reporting
-- ✓ Reusable SQL Views
--
-- These techniques are commonly used in enterprise reporting,
-- financial analytics, procurement analytics, and BI solutions.
-- ============================================================

-- ============================================================
-- END OF DEVELOPMENT
--
-- Completion of Phase 7 marks the conclusion of the SQL
-- development lifecycle for the Procurement Spend
-- Intelligence Platform.
--
-- The project now transitions to portfolio presentation,
-- including:
-- • Power BI dashboards
-- • GitHub documentation
-- • ER diagram
-- • Executive project presentation
--
-- The repository demonstrates:
-- • Data warehouse design
-- • Synthetic data generation
-- • Data validation
-- • Business analytics
-- • Advanced SQL analytics
-- ============================================================