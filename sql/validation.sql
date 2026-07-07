-- ============================================================
-- PROCUREMENT SPEND INTELLIGENCE PLATFORM
-- ============================================================
-- Phase 5: Data Quality Validation
-- File:    validation.sql
-- Purpose: Validate the integrity, completeness, and business quality of the
--          Procurement Spend Intelligence Platform after synthetic data generation.
-- DB:      DuckDB 1.5.x
-- ============================================================
-- This script verifies:
-- • Expected row counts
-- • Referential integrity
-- • Missing values
-- • Business rule compliance
-- • Data distributions
-- • Spend quality
-- • Supplier performance quality
-- • Overall data quality scorecard
-- Execute after: schema.sql, data_generation.sql
--
-- Validation Result:
-- Actual row counts should match the expected warehouse design.
-- ============================================================


-- ============================================================
-- SECTION 1: ROW COUNT VERIFICATION
-- ============================================================

SELECT 'dim_date'                  AS table_name, COUNT(*) AS row_count, '1,096' AS target FROM dim_date                  UNION ALL
SELECT 'dim_locations',                           COUNT(*),               '6'              FROM dim_locations             UNION ALL
SELECT 'dim_categories',                          COUNT(*),               '10'             FROM dim_categories            UNION ALL
SELECT 'dim_business_units',                      COUNT(*),               '8'              FROM dim_business_units        UNION ALL
SELECT 'dim_suppliers',                           COUNT(*),               '30'             FROM dim_suppliers             UNION ALL
SELECT 'fact_purchase_orders',                    COUNT(*),               '4,800'          FROM fact_purchase_orders      UNION ALL
SELECT 'fact_supplier_performance',               COUNT(*),               '900+'           FROM fact_supplier_performance
ORDER BY table_name;

-- Expected: all row_count values match target column


-- ============================================================
-- SECTION 2: REFERENTIAL INTEGRITY CHECKS
-- ============================================================

-- 2.1 Combined FK check — all relationships in one result
SELECT check_name, orphans,
       CASE WHEN orphans = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
    SELECT 'PO → dim_date'           AS check_name,
           COUNT(*) AS orphans
    FROM fact_purchase_orders f
    LEFT JOIN dim_date d ON f.date_id = d.date_id
    WHERE d.date_id IS NULL

    UNION ALL
    SELECT 'PO → dim_suppliers',
           COUNT(*)
    FROM fact_purchase_orders f
    LEFT JOIN dim_suppliers s ON f.supplier_id = s.supplier_id
    WHERE s.supplier_id IS NULL

    UNION ALL
    SELECT 'PO → dim_categories',
           COUNT(*)
    FROM fact_purchase_orders f
    LEFT JOIN dim_categories c ON f.category_id = c.category_id
    WHERE c.category_id IS NULL

    UNION ALL
    SELECT 'PO → dim_business_units',
           COUNT(*)
    FROM fact_purchase_orders f
    LEFT JOIN dim_business_units b ON f.business_unit_id = b.business_unit_id
    WHERE b.business_unit_id IS NULL

    UNION ALL
    SELECT 'PO → dim_locations',
           COUNT(*)
    FROM fact_purchase_orders f
    LEFT JOIN dim_locations l ON f.location_id = l.location_id
    WHERE l.location_id IS NULL

    UNION ALL
    SELECT 'Perf → dim_suppliers',
           COUNT(*)
    FROM fact_supplier_performance p
    LEFT JOIN dim_suppliers s ON p.supplier_id = s.supplier_id
    WHERE s.supplier_id IS NULL

    UNION ALL
    SELECT 'Perf → dim_date',
           COUNT(*)
    FROM fact_supplier_performance p
    LEFT JOIN dim_date d ON p.date_id = d.date_id
    WHERE d.date_id IS NULL
) checks
ORDER BY check_name;

-- Expected: orphans = 0 and result = PASS for every row


-- ============================================================
-- SECTION 3: NULL AND MISSING VALUE AUDIT
-- ============================================================

-- 3.1 Required field NULL check — fact_purchase_orders
SELECT
    COUNT(CASE WHEN po_id            IS NULL THEN 1 END) AS null_po_id,
    COUNT(CASE WHEN po_number        IS NULL THEN 1 END) AS null_po_number,
    COUNT(CASE WHEN date_id          IS NULL THEN 1 END) AS null_date_id,
    COUNT(CASE WHEN supplier_id      IS NULL THEN 1 END) AS null_supplier_id,
    COUNT(CASE WHEN category_id      IS NULL THEN 1 END) AS null_category_id,
    COUNT(CASE WHEN business_unit_id IS NULL THEN 1 END) AS null_bu_id,
    COUNT(CASE WHEN location_id      IS NULL THEN 1 END) AS null_location_id,
    COUNT(CASE WHEN total_amount     IS NULL THEN 1 END) AS null_total_amount,
    COUNT(CASE WHEN po_status        IS NULL THEN 1 END) AS null_po_status
FROM fact_purchase_orders;

-- Expected: every column = 0

-- 3.2 Conditional NULL check — verify NULLs follow business rules
-- Rejected/Cancelled → NULL payment, delivery dates, invoice
-- Pending            → NULL actual_delivery and days_late
-- Closed/Approved    → no unexpected NULLs
SELECT
    po_status,
    COUNT(*)                                                         AS po_count,
    COUNT(CASE WHEN payment_status    IS NULL THEN 1 END)            AS null_payment,
    COUNT(CASE WHEN expected_delivery IS NULL THEN 1 END)            AS null_exp_delivery,
    COUNT(CASE WHEN actual_delivery   IS NULL THEN 1 END)            AS null_act_delivery,
    COUNT(CASE WHEN days_late         IS NULL THEN 1 END)            AS null_days_late,
    COUNT(CASE WHEN invoice_number    IS NULL THEN 1 END)            AS null_invoice
FROM fact_purchase_orders
GROUP BY po_status
ORDER BY po_count DESC;

-- Expected:
--   Rejected  → null_payment = null_exp_delivery = null_invoice = po_count
--   Cancelled → same as Rejected
--   Pending   → null_act_delivery = null_days_late = po_count
--   Closed    → all null counts ≈ 0
--   Approved  → all null counts ≈ 0

-- 3.3 dim_suppliers — no critical NULLs
SELECT
    COUNT(CASE WHEN supplier_name IS NULL THEN 1 END) AS null_name,
    COUNT(CASE WHEN supplier_code IS NULL THEN 1 END) AS null_code,
    COUNT(CASE WHEN supplier_tier IS NULL THEN 1 END) AS null_tier,
    COUNT(CASE WHEN payment_terms IS NULL THEN 1 END) AS null_payment_terms,
    COUNT(CASE WHEN is_active     IS NULL THEN 1 END) AS null_is_active
FROM dim_suppliers;

-- Expected: all = 0


-- ============================================================
-- SECTION 4: DATA RANGE AND CONSTRAINT CHECKS
-- Values must fall within acceptable business bounds.
-- ============================================================

-- 4.1 Spend amount ranges
SELECT
    ROUND(MIN(total_amount), 2)                              AS min_amount,
    ROUND(MAX(total_amount), 2)                              AS max_amount,
    ROUND(AVG(total_amount), 2)                              AS avg_amount,
    COUNT(CASE WHEN total_amount <= 0    THEN 1 END)         AS zero_or_negative,
    COUNT(CASE WHEN total_amount > 1000000 THEN 1 END)       AS over_1m
FROM fact_purchase_orders;

-- Expected: min > 0, zero_or_negative = 0

-- 4.2 Date dimension coverage
SELECT
    MIN(full_date)        AS first_date,
    MAX(full_date)        AS last_date,
    COUNT(*)              AS total_days,
    COUNT(DISTINCT year)  AS distinct_years
FROM dim_date;

-- Expected: first = 2022-01-01, last = 2024-12-31, total_days = 1096, distinct_years = 3

-- 4.3 All PO dates within the 2022–2024 range
SELECT
    MIN(d.full_date)                                                   AS earliest_po_date,
    MAX(d.full_date)                                                   AS latest_po_date,
    COUNT(CASE WHEN d.full_date < DATE '2022-01-01' THEN 1 END)        AS before_range,
    COUNT(CASE WHEN d.full_date > DATE '2024-12-31' THEN 1 END)        AS after_range
FROM fact_purchase_orders f
JOIN dim_date d ON f.date_id = d.date_id;

-- Expected: before_range = 0, after_range = 0

-- 4.4 Supplier performance score ranges
SELECT
    MIN(risk_score)            AS min_risk,        MAX(risk_score)            AS max_risk,
    MIN(performance_score)     AS min_perf,        MAX(performance_score)     AS max_perf,
    MIN(on_time_delivery_rate) AS min_otd,         MAX(on_time_delivery_rate) AS max_otd,
    MIN(defect_rate)           AS min_defect,      MAX(defect_rate)           AS max_defect,
    COUNT(CASE WHEN risk_score < 1 OR risk_score > 10 THEN 1 END)             AS risk_out_of_range,
    COUNT(CASE WHEN performance_score < 1 OR performance_score > 10 THEN 1 END) AS perf_out_of_range
FROM fact_supplier_performance;

-- Expected: risk/perf between 1.0-10.0, OTD between 0-100, out_of_range counts = 0


-- ============================================================
-- SECTION 5: DISTRIBUTION CHECKS
-- ============================================================

-- 5.1 PO volume and spend by supplier tier
SELECT
    s.supplier_tier,
    COUNT(f.po_id)                                                                AS po_count,
    ROUND(COUNT(f.po_id) * 100.0 / SUM(COUNT(f.po_id)) OVER (), 1)               AS pct_of_pos,
    ROUND(SUM(f.total_amount) / 1000000.0, 2)                                     AS spend_millions,
    ROUND(SUM(f.total_amount) * 100.0 / SUM(SUM(f.total_amount)) OVER (), 1)      AS pct_of_spend,
    ROUND(AVG(f.total_amount), 0)                                                 AS avg_po_value
FROM fact_purchase_orders f
JOIN dim_suppliers s ON f.supplier_id = s.supplier_id
GROUP BY s.supplier_tier
ORDER BY spend_millions DESC;

-- Expected: Strategic ~50% of POs and ~50-55% of spend

-- 5.2 Spend and PO count by category
SELECT
    c.category_group,
    c.category_name,
    COUNT(f.po_id)                               AS po_count,
    ROUND(SUM(f.total_amount) / 1000000.0, 2)    AS spend_millions,
    ROUND(AVG(f.total_amount), 0)                AS avg_po_value
FROM fact_purchase_orders f
JOIN dim_categories c ON f.category_id = c.category_id
GROUP BY c.category_group, c.category_name
ORDER BY spend_millions DESC;

-- Expected: Raw Materials highest spend; Capital Equipment highest avg PO value

-- 5.3 Spend by business unit
SELECT
    b.business_unit_name,
    b.bu_code,
    COUNT(f.po_id)                               AS po_count,
    ROUND(SUM(f.total_amount) / 1000000.0, 2)    AS spend_millions
FROM fact_purchase_orders f
JOIN dim_business_units b ON f.business_unit_id = b.business_unit_id
GROUP BY b.business_unit_name, b.bu_code
ORDER BY spend_millions DESC;

-- Expected: Manufacturing (BU-MFG) highest spend by a significant margin

-- 5.4 Spend by location
SELECT
    l.location_name,
    l.city,
    l.location_type,
    COUNT(f.po_id)                               AS po_count,
    ROUND(SUM(f.total_amount) / 1000000.0, 2)    AS spend_millions
FROM fact_purchase_orders f
JOIN dim_locations l ON f.location_id = l.location_id
GROUP BY l.location_name, l.city, l.location_type
ORDER BY spend_millions DESC;

-- Expected: Houston Plant and Detroit Plant as top two spend sites

-- 5.5 Annual PO volume and spend trend
SELECT
    d.year,
    COUNT(f.po_id)                               AS po_count,
    ROUND(SUM(f.total_amount) / 1000000.0, 2)    AS spend_millions
FROM fact_purchase_orders f
JOIN dim_date d ON f.date_id = d.date_id
GROUP BY d.year
ORDER BY d.year;

-- Expected: roughly even distribution across 2022, 2023, 2024

-- 5.6 PO status distribution
SELECT
    po_status,
    COUNT(*)                                                        AS po_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)             AS pct
FROM fact_purchase_orders
GROUP BY po_status
ORDER BY po_count DESC;

-- Expected: Closed ~55% | Approved ~25% | Pending ~10% | Rejected ~7% | Cancelled ~3%


-- ============================================================
-- SECTION 6: SPEND QUALITY CHECKS
-- ============================================================

-- 6.1 Total spend summary (excluding Rejected/Cancelled)
SELECT
    COUNT(*)                                     AS active_po_count,
    ROUND(SUM(total_amount) / 1000000.0, 2)      AS total_spend_millions,
    ROUND(AVG(total_amount), 2)                  AS avg_po_value,
    ROUND(MIN(total_amount), 2)                  AS min_po_value,
    ROUND(MAX(total_amount), 2)                  AS max_po_value
FROM fact_purchase_orders
WHERE po_status NOT IN ('Rejected', 'Cancelled');

-- Expected: total spend ~$190–$240M; avg PO ~$45k–$65k

-- 6.2 Direct vs Indirect spend by year
SELECT
    d.year,
    c.category_group,
    ROUND(SUM(f.total_amount) / 1000000.0, 2)    AS spend_millions,
    COUNT(f.po_id)                               AS po_count
FROM fact_purchase_orders f
JOIN dim_date d       ON f.date_id     = d.date_id
JOIN dim_categories c ON f.category_id = c.category_id
WHERE f.po_status NOT IN ('Rejected', 'Cancelled')
GROUP BY d.year, c.category_group
ORDER BY d.year, c.category_group;

-- Expected: Direct spend > Indirect spend every year

-- 6.3 Payment status distribution
SELECT
    payment_status,
    COUNT(*)                                                        AS po_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)             AS pct,
    ROUND(SUM(total_amount) / 1000000.0, 2)                        AS spend_millions
FROM fact_purchase_orders
WHERE po_status NOT IN ('Rejected', 'Cancelled')
GROUP BY payment_status
ORDER BY po_count DESC;

-- Expected: Paid ~70% | Outstanding ~15% | Overdue ~10% | Disputed ~5%


-- ============================================================
-- SECTION 7: SUPPLIER PERFORMANCE TABLE CHECKS
-- ============================================================

-- 7.1 Coverage summary
SELECT
    COUNT(*)                          AS total_records,
    COUNT(DISTINCT f.supplier_id)     AS unique_suppliers,
    COUNT(DISTINCT f.date_id)         AS unique_months,
    MIN(d.full_date)                  AS earliest_month,
    MAX(d.full_date)                  AS latest_month
FROM fact_supplier_performance f
JOIN dim_date d ON f.date_id = d.date_id;

-- Expected: unique_suppliers = 30, unique_months <= 36

-- 7.2 KPI benchmarks by supplier tier
SELECT
    s.supplier_tier,
    COUNT(*)                                   AS records,
    ROUND(AVG(on_time_delivery_rate), 1)        AS avg_otd_pct,
    ROUND(AVG(defect_rate), 2)                  AS avg_defect_pct,
    ROUND(AVG(avg_lead_time_days), 1)           AS avg_lead_days,
    ROUND(AVG(risk_score), 2)                   AS avg_risk_score,
    ROUND(AVG(performance_score), 2)            AS avg_perf_score
FROM fact_supplier_performance f
JOIN dim_suppliers s ON f.supplier_id = s.supplier_id
GROUP BY s.supplier_tier
ORDER BY avg_otd_pct DESC;

-- Expected: Strategic best OTD (90%+) and lowest risk; Spot worst OTD and highest risk

-- 7.3 Duplicate record check (should return 0 rows)
SELECT supplier_id, date_id, COUNT(*) AS duplicates
FROM fact_supplier_performance
GROUP BY supplier_id, date_id
HAVING COUNT(*) > 1;

-- Expected: no rows returned

-- 7.4 Intentional deterioration check (suppliers 20, 24, 26)
-- Compares OTD rate in early 2022 vs late 2024
SELECT
    s.supplier_name,
    s.supplier_id,
    ROUND(AVG(CASE WHEN d.year = 2022 AND d.month <= 6
                   THEN f.on_time_delivery_rate END), 1)  AS otd_2022_h1,
    ROUND(AVG(CASE WHEN d.year = 2024 AND d.month >= 7
                   THEN f.on_time_delivery_rate END), 1)  AS otd_2024_h2,
    ROUND(
        AVG(CASE WHEN d.year = 2024 AND d.month >= 7 THEN f.on_time_delivery_rate END) -
        AVG(CASE WHEN d.year = 2022 AND d.month <= 6 THEN f.on_time_delivery_rate END)
    , 1)                                                  AS change_pp
FROM fact_supplier_performance f
JOIN dim_suppliers s ON f.supplier_id = s.supplier_id
JOIN dim_date      d ON f.date_id     = d.date_id
WHERE s.supplier_id IN (20, 24, 26)
GROUP BY s.supplier_name, s.supplier_id
ORDER BY change_pp;

-- Expected: all three show negative change_pp (declining OTD over time)
-- This is the deliberate story baked into the data for Phase 6/7 trend analysis.

-- 7.4B Corrected deterioration validation
-- Compare first available OTD vs last available OTD for suppliers 20, 24, and 26

WITH supplier_history AS (
    SELECT
        s.supplier_name,
        f.supplier_id,
        d.full_date,
        f.on_time_delivery_rate,
        ROW_NUMBER() OVER (
            PARTITION BY f.supplier_id
            ORDER BY d.full_date
        ) AS rn_first,
        ROW_NUMBER() OVER (
            PARTITION BY f.supplier_id
            ORDER BY d.full_date DESC
        ) AS rn_last
    FROM fact_supplier_performance f
    JOIN dim_suppliers s
        ON f.supplier_id = s.supplier_id
    JOIN dim_date d
        ON f.date_id = d.date_id
    WHERE f.supplier_id IN (20,24,26)
)

SELECT
    supplier_name,
    supplier_id,
    MAX(CASE WHEN rn_first = 1 THEN on_time_delivery_rate END) AS first_otd,
    MAX(CASE WHEN rn_last = 1 THEN on_time_delivery_rate END) AS last_otd,
    ROUND(
        MAX(CASE WHEN rn_last = 1 THEN on_time_delivery_rate END)
        -
        MAX(CASE WHEN rn_first = 1 THEN on_time_delivery_rate END),
        1
    ) AS change_pp
FROM supplier_history
GROUP BY supplier_name, supplier_id
ORDER BY change_pp;


-- ============================================================
-- SECTION 8: DATA QUALITY SCORECARD
--
-- Consolidates the results of all validation checks into a single
-- executive summary.
--
-- A PASS across every category indicates the warehouse is ready
-- for business analytics and dashboard development.
-- ============================================================

WITH
counts AS (
    SELECT
        (SELECT COUNT(*) FROM dim_date)                  AS n_date,
        (SELECT COUNT(*) FROM dim_suppliers)             AS n_sup,
        (SELECT COUNT(*) FROM fact_purchase_orders)      AS n_po,
        (SELECT COUNT(*) FROM fact_supplier_performance) AS n_perf
),
orphans AS (
    SELECT
        (SELECT COUNT(*) FROM fact_purchase_orders f LEFT JOIN dim_date d           ON f.date_id          = d.date_id          WHERE d.date_id IS NULL)          AS o1,
        (SELECT COUNT(*) FROM fact_purchase_orders f LEFT JOIN dim_suppliers s       ON f.supplier_id      = s.supplier_id      WHERE s.supplier_id IS NULL)       AS o2,
        (SELECT COUNT(*) FROM fact_purchase_orders f LEFT JOIN dim_categories c      ON f.category_id      = c.category_id      WHERE c.category_id IS NULL)      AS o3,
        (SELECT COUNT(*) FROM fact_purchase_orders f LEFT JOIN dim_business_units b  ON f.business_unit_id = b.business_unit_id WHERE b.business_unit_id IS NULL)  AS o4,
        (SELECT COUNT(*) FROM fact_purchase_orders f LEFT JOIN dim_locations l       ON f.location_id      = l.location_id      WHERE l.location_id IS NULL)      AS o5,
        (SELECT COUNT(*) FROM fact_supplier_performance p LEFT JOIN dim_suppliers s  ON p.supplier_id      = s.supplier_id      WHERE s.supplier_id IS NULL)       AS o6
),
nullchk AS (
    SELECT
        COUNT(CASE WHEN total_amount IS NULL THEN 1 END)     AS n1,
        COUNT(CASE WHEN supplier_id  IS NULL THEN 1 END)     AS n2,
        COUNT(CASE WHEN date_id      IS NULL THEN 1 END)     AS n3,
        COUNT(CASE WHEN po_status    IS NULL THEN 1 END)     AS n4
    FROM fact_purchase_orders
),
rangechk AS (
    SELECT COUNT(CASE WHEN total_amount <= 0 THEN 1 END) AS neg_amt
    FROM fact_purchase_orders
)
SELECT
    CASE WHEN c.n_date = 1096  THEN 'PASS' ELSE 'FAIL' END  AS dim_date_count,
    CASE WHEN c.n_sup  = 30    THEN 'PASS' ELSE 'FAIL' END  AS dim_suppliers_count,
    CASE WHEN c.n_po   = 4800  THEN 'PASS' ELSE 'FAIL' END  AS fact_po_count,
    CASE WHEN c.n_perf >= 900  THEN 'PASS' ELSE 'FAIL' END  AS fact_perf_count,
    CASE WHEN o.o1+o.o2+o.o3+o.o4+o.o5+o.o6 = 0
         THEN 'PASS' ELSE 'FAIL' END                         AS fk_integrity,
    CASE WHEN n.n1+n.n2+n.n3+n.n4 = 0
         THEN 'PASS' ELSE 'FAIL' END                         AS no_critical_nulls,
    CASE WHEN r.neg_amt = 0
         THEN 'PASS' ELSE 'FAIL' END                         AS no_negative_amounts
FROM counts c, orphans o, nullchk n, rangechk r;
