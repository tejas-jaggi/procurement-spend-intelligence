-- ============================================================
-- PROCUREMENT SPEND INTELLIGENCE PLATFORM
-- ============================================================
-- Phase 6: Procurement Business Analytics
-- File:    spend_analysis.sql
-- Purpose:
-- Transform validated procurement data into business insights that
-- support operational decision-making and executive reporting.
-- DB:      DuckDB 1.5.x
-- Company: Apex Manufacturing Group (AMG)
-- ============================================================
-- This script analyzes:
-- • Annual procurement spend
-- • Category performance
-- • Supplier concentration
-- • Business unit spending
-- • Geographic procurement activity
-- • Procurement trends
-- • Payment performance
-- • Supplier performance
--
-- Execute after:
--   1. schema.sql
--   2. data_generation.sql
--   3. validation.sql
-- ============================================================
-- Standard filter applied throughout:
-- po_status NOT IN ('Rejected', 'Cancelled')
-- Rejected and Cancelled POs never resulted in actual spend.
-- ============================================================

-- ============================================================
-- PHASE OVERVIEW
--
-- After validating the warehouse in Phase 5, this phase focuses on
-- transforming procurement data into actionable business insights.
--
-- Each query answers a realistic procurement question that could
-- support sourcing managers, procurement analysts, finance teams,
-- and executive leadership.
--
-- Together these analyses establish the analytical foundation for
-- the Power BI dashboards developed in the portfolio presentation stage.
-- ============================================================

-- ============================================================
-- 1. ANNUAL PROCUREMENT SPEND OVERVIEW
-- Business question: How much did AMG spend each year, 
-- and how is spending trending over time?
-- ============================================================

SELECT
    d.year,
    COUNT(f.po_id)                                AS po_count,
    ROUND(SUM(f.total_amount) / 1000000.0, 2)    AS spend_millions,
    ROUND(AVG(f.total_amount), 0)                 AS avg_po_value,
    ROUND(MIN(f.total_amount), 0)                 AS min_po_value,
    ROUND(MAX(f.total_amount), 0)                 AS max_po_value
FROM fact_purchase_orders f
JOIN dim_date d ON f.date_id = d.date_id
WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
GROUP BY d.year
ORDER BY d.year;

-- Key Business Insight:
-- Stable annual spend around $85-100M confirms AMG is a mature
-- manufacturer with predictable procurement cycles.
-- A rising trend signals growth; a flat trend signals stability.


-- ============================================================
-- 2. CATEGORY SPEND BREAKDOWN
-- Business question: Which spend categories consume the most
-- budget, and what percentage of total spend do they represent?
-- ============================================================

WITH total_spend AS (
    SELECT SUM(total_amount) AS grand_total
    FROM fact_purchase_orders
    WHERE po_status NOT IN ('Rejected', 'Cancelled')
)
SELECT
    c.category_group,
    c.category_name,
    c.category_code,
    COUNT(f.po_id)                                                    AS po_count,
    ROUND(SUM(f.total_amount) / 1000000.0, 2)                        AS spend_millions,
    ROUND(SUM(f.total_amount) * 100.0 / t.grand_total, 1)            AS pct_of_total,
    ROUND(AVG(f.total_amount), 0)                                     AS avg_po_value
FROM fact_purchase_orders f
JOIN dim_categories c ON f.category_id = c.category_id
CROSS JOIN total_spend t
WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
GROUP BY c.category_group, c.category_name, c.category_code, t.grand_total
ORDER BY spend_millions DESC;

-- Key Business Insight:
-- Raw Materials and Industrial Components should dominate —
-- this confirms AMG is production-heavy (Direct spend dominates).
-- If Indirect categories were growing faster, that would be
-- a cost reduction opportunity.


-- ============================================================
-- 3. TOP 10 SUPPLIERS BY TOTAL SPEND
-- Business question: Which suppliers receive the most money?
-- Business Objective:
-- Identify the suppliers receiving the highest procurement spend
-- and evaluate potential supplier concentration risk.
-- ============================================================

WITH total_spend AS (
    SELECT SUM(total_amount) AS grand_total
    FROM fact_purchase_orders
    WHERE po_status NOT IN ('Rejected', 'Cancelled')
)
SELECT
    s.supplier_name,
    s.supplier_code,
    s.supplier_tier,
    s.region,
    COUNT(f.po_id)                                                    AS po_count,
    ROUND(SUM(f.total_amount) / 1000000.0, 2)                        AS spend_millions,
    ROUND(SUM(f.total_amount) * 100.0 / t.grand_total, 1)            AS pct_of_total_spend,
    ROUND(AVG(f.total_amount), 0)                                     AS avg_po_value
FROM fact_purchase_orders f
JOIN dim_suppliers s  ON f.supplier_id = s.supplier_id
CROSS JOIN total_spend t
WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
GROUP BY s.supplier_name, s.supplier_code, s.supplier_tier, s.region, t.grand_total
ORDER BY spend_millions DESC
LIMIT 10;

-- Key Business Insight:
-- The top supplier likely accounts for 10-12% of total spend.
-- Dependency on a single supplier above 15% is a concentration risk.
-- Strategic suppliers (SUP-001 through SUP-005) should dominate this list.


-- ============================================================
-- 4. SUPPLIER TIER SPEND ANALYSIS
-- Business question: How is spend distributed across supplier
-- tiers? Is AMG over-relying on Strategic suppliers?
-- ============================================================

WITH total_spend AS (
    SELECT SUM(total_amount) AS grand_total
    FROM fact_purchase_orders
    WHERE po_status NOT IN ('Rejected', 'Cancelled')
)
SELECT
    s.supplier_tier,
    COUNT(DISTINCT s.supplier_id)                                     AS supplier_count,
    COUNT(f.po_id)                                                    AS po_count,
    ROUND(COUNT(f.po_id) * 100.0 / SUM(COUNT(f.po_id)) OVER (), 1)  AS pct_of_pos,
    ROUND(SUM(f.total_amount) / 1000000.0, 2)                        AS spend_millions,
    ROUND(SUM(f.total_amount) * 100.0 / t.grand_total, 1)            AS pct_of_spend,
    ROUND(AVG(f.total_amount), 0)                                     AS avg_po_value
FROM fact_purchase_orders f
JOIN dim_suppliers s ON f.supplier_id = s.supplier_id
CROSS JOIN total_spend t
WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
GROUP BY s.supplier_tier, t.grand_total
ORDER BY spend_millions DESC;

-- Key Business Insight:
-- Strategic suppliers should account for ~50-55% of spend.
-- Spot supplier spend above 5% is a procurement red flag —
-- it means too many emergency purchases at premium rates.


-- ============================================================
-- 5. BUSINESS UNIT SPEND ANALYSIS
-- Business question: Which departments are driving spend,
-- and are they aligned with their annual budgets?
-- ============================================================

SELECT
    b.business_unit_name,
    b.bu_code,
    b.annual_budget,
    COUNT(f.po_id)                                                    AS po_count,
    ROUND(SUM(f.total_amount) / 1000000.0, 2)                        AS spend_millions,
    ROUND(AVG(f.total_amount), 0)                                     AS avg_po_value,
    ROUND(SUM(f.total_amount) * 100.0
          / SUM(SUM(f.total_amount)) OVER (), 1)                      AS pct_of_total_spend,
    -- Budget utilization rate over 3 years vs 3-year budget
    ROUND(SUM(f.total_amount) / (b.annual_budget * 3.0) * 100, 1)    AS budget_utilization_3yr_pct
FROM fact_purchase_orders f
JOIN dim_business_units b ON f.business_unit_id = b.business_unit_id
WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
GROUP BY b.business_unit_name, b.bu_code, b.annual_budget
ORDER BY spend_millions DESC;

-- Key Business Insight:
-- Manufacturing (BU-MFG) should dominate, reflecting production-driven spend.
-- budget_utilization_3yr_pct over 100% means the department overspent.
-- This query is exactly what a finance-facing analyst would build.


-- ============================================================
-- 6. GEOGRAPHIC SPEND ANALYSIS
-- Business question: Which AMG facilities drive the most
-- procurement spend?
-- ============================================================

SELECT
    l.location_name,
    l.city,
    l.state,
    l.location_type,
    COUNT(f.po_id)                                                    AS po_count,
    ROUND(SUM(f.total_amount) / 1000000.0, 2)                        AS spend_millions,
    ROUND(SUM(f.total_amount) * 100.0
          / SUM(SUM(f.total_amount)) OVER (), 1)                      AS pct_of_total_spend,
    ROUND(AVG(f.total_amount), 0)                                     AS avg_po_value
FROM fact_purchase_orders f
JOIN dim_locations l ON f.location_id = l.location_id
WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
GROUP BY l.location_name, l.city, l.state, l.location_type
ORDER BY spend_millions DESC;

-- Key Business Insight:
-- Houston Plant and Detroit Plant should lead — they are the
-- production sites consuming raw materials and components.
-- High spend at Chicago HQ on Professional Services or IT
-- is expected for a corporate headquarters.


-- ============================================================
-- 7. MONTHLY SPEND TREND (2022–2024)
-- Business question: Is procurement spend seasonal?
-- Are there consistent spend spikes or dips by month?
-- ============================================================

SELECT
    d.year,
    d.month,
    d.month_name,
    d.month_label,
    COUNT(f.po_id)                                AS po_count,
    ROUND(SUM(f.total_amount) / 1000000.0, 3)    AS spend_millions
FROM fact_purchase_orders f
JOIN dim_date d ON f.date_id = d.date_id
WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
GROUP BY d.year, d.month, d.month_name, d.month_label
ORDER BY d.year, d.month;

-- Key Business Insight:
-- Real manufacturers typically see spend spikes in Q2 (spring production ramp)
-- and dips in December (fiscal year-end purchasing freezes).
-- Use this query output to build a line chart in your portfolio.


-- ============================================================
-- 8. QUARTERLY EXECUTIVE SUMMARY
-- Business question: How does spend look quarter by quarter?
-- This is the format most used in executive procurement reviews.
-- ============================================================

SELECT
    d.year,
    d.quarter,
    d.quarter_label,
    COUNT(f.po_id)                                AS po_count,
    ROUND(SUM(f.total_amount) / 1000000.0, 2)    AS spend_millions,
    ROUND(AVG(f.total_amount), 0)                 AS avg_po_value,
    COUNT(DISTINCT f.supplier_id)                 AS active_suppliers,
    COUNT(DISTINCT f.category_id)                 AS active_categories
FROM fact_purchase_orders f
JOIN dim_date d ON f.date_id = d.date_id
WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
GROUP BY d.year, d.quarter, d.quarter_label
ORDER BY d.year, d.quarter;

-- Key Business Insight:
-- Quarterly breakdowns are what procurement leadership sees.
-- active_suppliers dropping in a quarter signals consolidation.
-- active_categories dropping signals possible budget constraints.


-- ============================================================
-- 9. DIRECT vs INDIRECT SPEND — YEAR-OVER-YEAR PIVOT
-- Business question: Is AMG's mix of Direct (production) and
-- Indirect (operational) spend shifting over time?
-- ============================================================

SELECT
    d.year,
    ROUND(SUM(CASE WHEN c.category_group = 'Direct'   THEN f.total_amount ELSE 0 END) / 1000000.0, 2) AS direct_spend_millions,
    ROUND(SUM(CASE WHEN c.category_group = 'Indirect' THEN f.total_amount ELSE 0 END) / 1000000.0, 2) AS indirect_spend_millions,
    ROUND(SUM(f.total_amount) / 1000000.0, 2)                                                          AS total_spend_millions,
    ROUND(SUM(CASE WHEN c.category_group = 'Direct'   THEN f.total_amount ELSE 0 END)
          * 100.0 / SUM(f.total_amount), 1)                                                            AS direct_pct,
    ROUND(SUM(CASE WHEN c.category_group = 'Indirect' THEN f.total_amount ELSE 0 END)
          * 100.0 / SUM(f.total_amount), 1)                                                            AS indirect_pct
FROM fact_purchase_orders f
JOIN dim_date d       ON f.date_id     = d.date_id
JOIN dim_categories c ON f.category_id = c.category_id
WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
GROUP BY d.year
ORDER BY d.year;

-- Key Business Insight:
-- A healthy manufacturer should have 60-70% Direct spend.
-- If Indirect % is growing year over year, it is a cost-reduction
-- target — too much spend on operations vs production.
-- CASE WHEN pivot is one of the most used techniques in analyst SQL.


-- ============================================================
-- 10. CATEGORY SPEND — YEAR-OVER-YEAR COMPARISON
-- Business question: Which categories are growing in cost?
-- Which are shrinking? Where are the escalation risks?
-- ============================================================

SELECT
    c.category_name,
    c.category_group,
    ROUND(SUM(CASE WHEN d.year = 2022 THEN f.total_amount ELSE 0 END) / 1000000.0, 2) AS spend_2022,
    ROUND(SUM(CASE WHEN d.year = 2023 THEN f.total_amount ELSE 0 END) / 1000000.0, 2) AS spend_2023,
    ROUND(SUM(CASE WHEN d.year = 2024 THEN f.total_amount ELSE 0 END) / 1000000.0, 2) AS spend_2024,
    ROUND(SUM(f.total_amount) / 1000000.0, 2)                                         AS total_3yr_spend,
    -- Year-over-year change calculation without window functions
    ROUND(
        (SUM(CASE WHEN d.year = 2023 THEN f.total_amount ELSE 0 END) -
         SUM(CASE WHEN d.year = 2022 THEN f.total_amount ELSE 0 END))
        * 100.0 /
        NULLIF(SUM(CASE WHEN d.year = 2022 THEN f.total_amount ELSE 0 END), 0)
    , 1)                                                                               AS growth_22_to_23_pct,
    ROUND(
        (SUM(CASE WHEN d.year = 2024 THEN f.total_amount ELSE 0 END) -
         SUM(CASE WHEN d.year = 2023 THEN f.total_amount ELSE 0 END))
        * 100.0 /
        NULLIF(SUM(CASE WHEN d.year = 2023 THEN f.total_amount ELSE 0 END), 0)
    , 1)                                                                               AS growth_23_to_24_pct
FROM fact_purchase_orders f
JOIN dim_date d       ON f.date_id     = d.date_id
JOIN dim_categories c ON f.category_id = c.category_id
WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
GROUP BY c.category_name, c.category_group
ORDER BY total_3yr_spend DESC;

-- Key Business Insight:
-- Any category showing 10%+ growth year-over-year warrants investigation.
-- Is the price increasing (inflation)? Is volume increasing (more production)?
-- This is a core procurement cost escalation analysis.
-- NULLIF prevents division-by-zero errors — important defensive SQL technique.


-- ============================================================
-- 11. LATE DELIVERY IMPACT ANALYSIS
-- Business question: Which suppliers consistently deliver late?
-- What is the average delay, and which categories are affected?
-- ============================================================

SELECT
    s.supplier_name,
    s.supplier_tier,
    s.region,
    COUNT(f.po_id)                                                          AS delivered_pos,
    COUNT(CASE WHEN f.days_late > 0 THEN 1 END)                            AS late_pos,
    ROUND(COUNT(CASE WHEN f.days_late > 0 THEN 1 END) * 100.0
          / COUNT(f.po_id), 1)                                              AS late_delivery_pct,
    COUNT(CASE WHEN f.days_late = 0 THEN 1 END)                            AS on_time_pos,
    ROUND(AVG(CASE WHEN f.days_late > 0 THEN f.days_late END), 1)          AS avg_days_late_when_late,
    MAX(f.days_late)                                                        AS worst_delay_days,
    ROUND(SUM(f.total_amount) / 1000000.0, 2)                              AS spend_millions
FROM fact_purchase_orders f
JOIN dim_suppliers s ON f.supplier_id = s.supplier_id
WHERE f.po_status IN ('Closed', 'Approved')
  AND f.days_late IS NOT NULL
GROUP BY s.supplier_name, s.supplier_tier, s.region
HAVING COUNT(f.po_id) >= 5
ORDER BY late_delivery_pct DESC
LIMIT 15;

-- Key Business Insight:
-- Suppliers with late_delivery_pct > 30% are procurement risks.
-- High spend + high late_delivery_pct = the most dangerous combination.
-- Strategic suppliers should appear at the bottom of this list.
-- Spot/Approved suppliers with high late rates are candidates for removal.


-- ============================================================
-- 12. PAYMENT HEALTH DASHBOARD
-- Business question: How healthy are AMG's outstanding payments?
-- How much money is at risk in Overdue or Disputed status?
-- ============================================================

SELECT
    payment_status,
    COUNT(f.po_id)                                                    AS invoice_count,
    ROUND(SUM(f.total_amount) / 1000000.0, 2)                        AS amount_millions,
    ROUND(SUM(f.total_amount) * 100.0
          / SUM(SUM(f.total_amount)) OVER (), 1)                      AS pct_of_active_spend,
    ROUND(AVG(f.total_amount), 0)                                     AS avg_invoice_value
FROM fact_purchase_orders f
WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
  AND f.payment_status IS NOT NULL
GROUP BY payment_status
ORDER BY amount_millions DESC;

-- Key Business Insight:
-- Outstanding + Overdue + Disputed combined is the total "at-risk" amount.
-- Overdue invoices incur penalty interest in most supplier contracts.
-- Disputed invoices signal receiving issues or quality disputes.
-- Finance teams use this exact view to manage cash flow forecasting.


-- ============================================================
-- 13. SUPPLIER SPEND CONCENTRATION
-- Business question: How many suppliers account for 80% of spend?
-- Are we dangerously dependent on a few vendors?
-- ============================================================

WITH
supplier_totals AS (
    SELECT
        s.supplier_id,
        s.supplier_name,
        s.supplier_tier,
        SUM(f.total_amount) AS spend
    FROM fact_purchase_orders f
    JOIN dim_suppliers s ON f.supplier_id = s.supplier_id
    WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
    GROUP BY s.supplier_id, s.supplier_name, s.supplier_tier
),
grand AS (
    SELECT SUM(spend) AS total FROM supplier_totals
)
SELECT
    st.supplier_name,
    st.supplier_tier,
    ROUND(st.spend / 1000000.0, 2)              AS spend_millions,
    ROUND(st.spend * 100.0 / g.total, 1)        AS pct_of_total
FROM supplier_totals st
CROSS JOIN grand g
ORDER BY st.spend DESC;

-- Key Business Insight:
-- If the top 5 suppliers (out of 30) account for >50% of spend,
-- AMG has high supplier concentration risk.
-- Disruption to any one of those 5 would immediately impact production.
-- This data supports the case for supplier diversification strategy.
-- Phase 7 will extend this with a full Pareto (80/20) analysis
-- using window functions and running totals.


-- ============================================================
-- 14. SUPPLIER PERFORMANCE SCORECARD ANALYSIS
-- Business question: Who are the best and worst performing
-- suppliers across all KPIs?
-- ============================================================

SELECT
    s.supplier_name,
    s.supplier_tier,
    s.payment_terms,
    COUNT(p.performance_id)                      AS months_tracked,
    ROUND(AVG(p.on_time_delivery_rate), 1)        AS avg_otd_pct,
    ROUND(AVG(p.defect_rate), 2)                  AS avg_defect_pct,
    ROUND(AVG(p.order_accuracy_rate), 1)          AS avg_accuracy_pct,
    ROUND(AVG(p.avg_lead_time_days), 1)           AS avg_lead_days,
    ROUND(AVG(p.risk_score), 1)                   AS avg_risk_score,
    ROUND(AVG(p.performance_score), 1)            AS avg_perf_score,
    -- Overall health flag
    CASE
        WHEN AVG(p.risk_score) >= 7               THEN 'HIGH RISK'
        WHEN AVG(p.risk_score) >= 4               THEN 'MEDIUM RISK'
        ELSE                                           'LOW RISK'
    END                                           AS risk_category
FROM fact_supplier_performance p
JOIN dim_suppliers s ON p.supplier_id = s.supplier_id
GROUP BY s.supplier_name, s.supplier_tier, s.payment_terms
ORDER BY avg_risk_score DESC;

-- Key Business Insight:
-- This is a supplier scorecard — the core deliverable of any
-- supplier management program.
-- HIGH RISK suppliers with significant spend should be flagged
-- for immediate supplier development meetings.
-- avg_perf_score < 4 combined with high spend = escalation candidate.


-- ============================================================
-- 15A. DETERIORATING SUPPLIER ALERT
-- Business question: Which suppliers have declining on-time
-- delivery performance? This is an early warning system.
--
-- Special focus: Suppliers 20 (ToolMaster), 24 (Summit Chemical),
-- and 26 (ProFreight) were designed with intentional decline.
-- ============================================================

WITH
first_half AS (
    SELECT
        p.supplier_id,
        ROUND(AVG(p.on_time_delivery_rate), 1) AS otd_early
    FROM fact_supplier_performance p
    JOIN dim_date d ON p.date_id = d.date_id
    WHERE d.year = 2022 OR (d.year = 2023 AND d.month <= 6)
    GROUP BY p.supplier_id
),
second_half AS (
    SELECT
        p.supplier_id,
        ROUND(AVG(p.on_time_delivery_rate), 1) AS otd_recent
    FROM fact_supplier_performance p
    JOIN dim_date d ON p.date_id = d.date_id
    WHERE d.year = 2024 OR (d.year = 2023 AND d.month >= 7)
    GROUP BY p.supplier_id
)
SELECT
    s.supplier_name,
    s.supplier_tier,
    s.supplier_code,
    f.otd_early                                           AS otd_2022_to_2023h1_pct,
    sh.otd_recent                                         AS otd_2023h2_to_2024_pct,
    ROUND(sh.otd_recent - f.otd_early, 1)                AS change_pp,
    CASE
        WHEN sh.otd_recent - f.otd_early <= -10          THEN 'CRITICAL DECLINE'
        WHEN sh.otd_recent - f.otd_early <= -5           THEN 'MODERATE DECLINE'
        WHEN sh.otd_recent - f.otd_early <= -2           THEN 'SLIGHT DECLINE'
        ELSE                                                  'STABLE'
    END                                                   AS trend_status
FROM first_half f
JOIN second_half sh ON f.supplier_id = sh.supplier_id
JOIN dim_suppliers s ON f.supplier_id = s.supplier_id
ORDER BY change_pp ASC;

-- Key Business Insight:
-- Suppliers flagged as CRITICAL DECLINE should be put on
-- a formal Supplier Improvement Plan (SIP).
-- This is exactly the SQL a procurement analyst runs in
-- quarterly business review preparation.
-- In your portfolio: "I designed the dataset to embed a supplier
-- deterioration signal and then built a query to surface it."
-- That is a complete data-to-insight story.

-- ============================================================
-- 15B. Validated Supplier Deterioration Analysis
-- Compare FIRST recorded OTD vs LAST recorded OTD
-- for every supplier.
--
-- This is the statistically correct methodology
-- validated during Phase 5.
-- ============================================================

WITH supplier_history AS (

    SELECT
        supplier_id,
        date_id,
        on_time_delivery_rate,

        ROW_NUMBER() OVER (
            PARTITION BY supplier_id
            ORDER BY date_id
        ) AS first_row,

        ROW_NUMBER() OVER (
            PARTITION BY supplier_id
            ORDER BY date_id DESC
        ) AS last_row

    FROM fact_supplier_performance

),

first_otd AS (

    SELECT
        supplier_id,
        on_time_delivery_rate AS first_otd_pct
    FROM supplier_history
    WHERE first_row = 1

),

last_otd AS (

    SELECT
        supplier_id,
        on_time_delivery_rate AS last_otd_pct
    FROM supplier_history
    WHERE last_row = 1

)

SELECT

    s.supplier_name,
    s.supplier_code,
    s.supplier_tier,

    ROUND(f.first_otd_pct, 1) AS first_otd_pct,
    ROUND(l.last_otd_pct, 1) AS last_otd_pct,

    ROUND(
        l.last_otd_pct - f.first_otd_pct,
        1
    ) AS change_pp,

    CASE
        WHEN (l.last_otd_pct - f.first_otd_pct) <= -10
            THEN 'CRITICAL DECLINE'

        WHEN (l.last_otd_pct - f.first_otd_pct) <= -5
            THEN 'MODERATE DECLINE'

        WHEN (l.last_otd_pct - f.first_otd_pct) <= -2
            THEN 'SLIGHT DECLINE'

        WHEN ABS(l.last_otd_pct - f.first_otd_pct) < 2
            THEN 'STABLE'

        ELSE 'IMPROVING'
    END AS trend_status

FROM dim_suppliers s
JOIN first_otd f
    ON s.supplier_id = f.supplier_id
JOIN last_otd l
    ON s.supplier_id = l.supplier_id

ORDER BY change_pp ASC;

-- ============================================================
-- END OF PHASE 6
--
-- This analysis transforms validated procurement data into
-- business insights supporting executive reporting,
-- sourcing decisions, supplier management, and spend optimization.
-- ============================================================