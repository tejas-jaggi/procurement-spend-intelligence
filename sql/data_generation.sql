-- ============================================================
-- PROCUREMENT SPEND INTELLIGENCE PLATFORM
-- ============================================================
-- File:    data_generation.sql
-- Phase   : 4 (Synthetic Data Generation)
-- Company: Apex Manufacturing Group (AMG)
-- Purpose : Populate all dimension and fact tables with
--           realistic procurement data for analytics.
-- Database: DuckDB 1.5.x
-- Period:  2022-01-01 → 2024-12-31  (3 fiscal years)
-- ============================================================
-- Prerequisite:
-- Execute schema.sql before running this script.  
--
-- Expected row counts after successful execution:
--   dim_date               → 1,096
--   dim_locations          →     6
--   dim_categories         →    10
--   dim_business_units     →     8
--   dim_suppliers          →    30
--   fact_purchase_orders   → 4,800
--   fact_supplier_performance → 900+
-- ============================================================


-- ============================================================
-- 1. dim_date  — full calendar spine, one row per day
-- ============================================================
INSERT INTO dim_date
SELECT
    CAST(strftime('%Y%m%d', d) AS INTEGER)                              AS date_id,
    d                                                                    AS full_date,
    CAST(extract(year    FROM d) AS INTEGER)                             AS year,
    CAST(extract(quarter FROM d) AS INTEGER)                             AS quarter,
    'Q' || CAST(extract(quarter FROM d) AS VARCHAR)
        || ' ' || CAST(extract(year FROM d) AS VARCHAR)                  AS quarter_label,
    CAST(extract(month   FROM d) AS INTEGER)                             AS month,
    strftime('%B', d)                                                    AS month_name,
    strftime('%b', d) || '-'
        || right(CAST(extract(year FROM d) AS VARCHAR), 2)               AS month_label,
    CAST(extract(week    FROM d) AS INTEGER)                             AS week,
    CAST(extract(isodow  FROM d) AS INTEGER)                             AS day_of_week,
    strftime('%A', d)                                                    AS day_name,
    extract(isodow FROM d) <= 5                                          AS is_weekday,
    CAST(extract(year    FROM d) AS INTEGER)                             AS fiscal_year,
    CAST(extract(quarter FROM d) AS INTEGER)                             AS fiscal_quarter
FROM (
    SELECT (DATE '2022-01-01' + CAST(i AS INTEGER)) AS d
    FROM   (SELECT unnest(generate_series(0, 1095)) AS i)
);


-- ============================================================
-- 2. dim_locations  — 6 AMG facilities
--
-- One row per company location.
-- Loads the six facilities that make up Apex Manufacturing
-- Group's operating footprint.
-- ============================================================
INSERT INTO dim_locations
    (location_id, location_name, city, state, country, region, location_type)
VALUES
    (1, 'Chicago HQ',                  'Chicago',  'IL', 'USA', 'Midwest',   'HQ'),
    (2, 'Houston Plant',               'Houston',  'TX', 'USA', 'South',     'Plant'),
    (3, 'Detroit Plant',               'Detroit',  'MI', 'USA', 'Midwest',   'Plant'),
    (4, 'Atlanta Distribution Center', 'Atlanta',  'GA', 'USA', 'Southeast', 'Distribution Center'),
    (5, 'Dallas Warehouse',            'Dallas',   'TX', 'USA', 'South',     'Warehouse'),
    (6, 'Columbus R&D Center',         'Columbus', 'OH', 'USA', 'Midwest',   'Office');


-- ============================================================
-- 3. dim_categories  — 10 spend categories (Direct + Indirect)
--
-- One row per procurement spend category.
-- Includes both Direct and Indirect spend classifications.
-- ============================================================
INSERT INTO dim_categories
    (category_id, category_name, category_group, category_code,
     subcategory, description, annual_budget)
VALUES
    (1,  'Raw Materials',           'Direct',   'CAT-RM',  'Steel & Metals',
         'Steel, aluminum, and industrial metals for manufacturing',           30000000),
    (2,  'Packaging',               'Direct',   'CAT-PKG', 'Industrial Packaging',
         'Boxes, pallets, shrink wrap, and protective materials',               8000000),
    (3,  'Industrial Components',   'Direct',   'CAT-IC',  'Parts & Assemblies',
         'Precision parts, sub-assemblies, and components',                    18000000),
    (4,  'Chemicals & Consumables', 'Direct',   'CAT-CHM', 'Process Chemicals',
         'Process chemicals, lubricants, and consumable materials',             6000000),
    (5,  'Logistics & Freight',     'Indirect', 'CAT-LOG', 'Transportation',
         'Inbound freight, outbound shipping, and 3PL services',               12000000),
    (6,  'MRO',                     'Indirect', 'CAT-MRO', 'Maintenance & Repair',
         'Tools, spare parts, and maintenance supplies',                        4000000),
    (7,  'IT Hardware & Software',  'Indirect', 'CAT-IT',  'Technology',
         'Computers, servers, software licenses, and SaaS subscriptions',       8000000),
    (8,  'Professional Services',   'Indirect', 'CAT-PS',  'Consulting & Advisory',
         'Consulting, legal, auditing, and staffing services',                  6000000),
    (9,  'Facilities & Utilities',  'Indirect', 'CAT-FAC', 'Building Services',
         'Facility maintenance, cleaning, security, and utilities',             3000000),
    (10, 'Capital Equipment',       'Direct',   'CAT-CAP', 'Machinery',
         'Heavy machinery and manufacturing equipment',                         5000000);


-- ============================================================
-- 4. dim_business_units  — 8 AMG departments
--
-- One row per business unit.
-- Used for departmental spend allocation and reporting.
-- ============================================================
INSERT INTO dim_business_units
    (business_unit_id, business_unit_name, bu_code, department,
     cost_center, manager_name, annual_budget, region)
VALUES
    (1, 'Manufacturing',          'BU-MFG',  'Manufacturing', 'CC-1100', 'Elena Vasquez',   45000000, 'Midwest'),
    (2, 'Supply Chain',           'BU-SCM',  'Supply Chain',  'CC-1200', 'James Okafor',    18000000, 'National'),
    (3, 'Operations',             'BU-OPS',  'Operations',    'CC-1300', 'Sandra Mitchell', 12000000, 'National'),
    (4, 'Finance',                'BU-FIN',  'Finance',       'CC-1400', 'Richard Chen',     3000000, 'Midwest'),
    (5, 'Information Technology', 'BU-IT',   'Technology',    'CC-1500', 'Priya Sharma',     8000000, 'Midwest'),
    (6, 'Research & Development', 'BU-RD',   'R&D',           'CC-1600', 'Dr. Mark Evans',   7000000, 'Midwest'),
    (7, 'Sales & Marketing',      'BU-SAL',  'Sales',         'CC-1700', 'Laura Fontaine',   4000000, 'National'),
    (8, 'Corporate Services',     'BU-CORP', 'Corporate',     'CC-1800', 'Thomas Wright',    3000000, 'Midwest');


-- ============================================================
-- 5. dim_suppliers  — 30 suppliers across 4 tiers
-- ============================================================
INSERT INTO dim_suppliers
    (supplier_id, supplier_name, supplier_code, region, country, city,
     supplier_tier, category_focus, payment_terms, company_size,
     contact_name, contact_email, is_active, onboarding_date)
VALUES
-- STRATEGIC (5)
(1,  'SteelCore Industries',       'SUP-001', 'Midwest',   'USA', 'Chicago',      'Strategic', 'Raw Materials',           'Net 60', 'Large',      'Michael Torres',  'm.torres@steelcore.com',    TRUE, DATE '2019-03-15'),
(2,  'GlobalPak Solutions',        'SUP-002', 'Southeast', 'USA', 'Atlanta',      'Strategic', 'Packaging',               'Net 30', 'Large',      'Sandra Kim',      's.kim@globalpak.com',       TRUE, DATE '2018-07-01'),
(3,  'TransAmerica Freight',       'SUP-003', 'National',  'USA', 'Dallas',       'Strategic', 'Logistics & Freight',     'Net 30', 'Enterprise', 'Robert Chen',     'r.chen@tafreight.com',      TRUE, DATE '2017-11-20'),
(4,  'Crestline Components',       'SUP-004', 'Midwest',   'USA', 'Detroit',      'Strategic', 'Industrial Components',   'Net 60', 'Large',      'Jennifer Walsh',  'j.walsh@crestline.com',     TRUE, DATE '2018-02-28'),
(5,  'NexTech Systems',            'SUP-005', 'West',      'USA', 'San Jose',     'Strategic', 'IT Hardware & Software',  'Net 30', 'Enterprise', 'David Park',      'd.park@nextech.com',        TRUE, DATE '2020-01-15'),
-- PREFERRED (11)
(6,  'Midwest Metals Co.',         'SUP-006', 'Midwest',   'USA', 'Cleveland',    'Preferred', 'Raw Materials',           'Net 60', 'Medium',     'Laura Simmons',   'l.simmons@mwmetals.com',    TRUE, DATE '2019-08-12'),
(7,  'PrimeChemical Supply',       'SUP-007', 'Southeast', 'USA', 'Houston',      'Preferred', 'Chemicals & Consumables', 'Net 45', 'Medium',     'Carlos Espinoza', 'c.espinoza@primechem.com',  TRUE, DATE '2020-03-01'),
(8,  'Atlas Packaging Group',      'SUP-008', 'Northeast', 'USA', 'Philadelphia', 'Preferred', 'Packaging',               'Net 30', 'Medium',     'Michelle Brooks', 'm.brooks@atlaspkg.com',     TRUE, DATE '2019-11-05'),
(9,  'FastLane Logistics',         'SUP-009', 'Southeast', 'USA', 'Charlotte',    'Preferred', 'Logistics & Freight',     'Net 30', 'Medium',     'Kevin Young',     'k.young@fastlane.com',      TRUE, DATE '2020-06-15'),
(10, 'Cardinal MRO Supply',        'SUP-010', 'Midwest',   'USA', 'Columbus',     'Preferred', 'MRO',                     'Net 30', 'Medium',     'Amy Johnson',     'a.johnson@cardinalmro.com', TRUE, DATE '2021-01-10'),
(11, 'Pinnacle Consulting Group',  'SUP-011', 'Northeast', 'USA', 'New York',     'Preferred', 'Professional Services',   'Net 30', 'Large',      'Thomas Reid',     't.reid@pinnacle.com',       TRUE, DATE '2019-05-20'),
(12, 'BuildRight Facilities',      'SUP-012', 'Midwest',   'USA', 'Indianapolis', 'Preferred', 'Facilities & Utilities',  'Net 45', 'Medium',     'Nancy Porter',    'n.porter@buildright.com',   TRUE, DATE '2020-09-01'),
(13, 'DataEdge Software',          'SUP-013', 'West',      'USA', 'Austin',       'Preferred', 'IT Hardware & Software',  'Net 30', 'Medium',     'James Liu',       'j.liu@dataedge.com',        TRUE, DATE '2021-03-15'),
(14, 'Hartwell Components',        'SUP-014', 'Northeast', 'USA', 'Boston',       'Preferred', 'Industrial Components',   'Net 60', 'Medium',     'Rachel Green',    'r.green@hartwell.com',      TRUE, DATE '2019-12-01'),
(15, 'Inland Chemical Corp.',      'SUP-015', 'Midwest',   'USA', 'Cincinnati',   'Preferred', 'Chemicals & Consumables', 'Net 45', 'Large',      'Peter Nguyen',    'p.nguyen@inlandchem.com',   TRUE, DATE '2018-10-15'),
(16, 'SkyFreight Services',        'SUP-016', 'West',      'USA', 'Los Angeles',  'Preferred', 'Logistics & Freight',     'Net 30', 'Medium',     'Diana Scott',     'd.scott@skyfreight.com',    TRUE, DATE '2020-12-01'),
-- APPROVED (11)
(17, 'Great Lakes Steel',          'SUP-017', 'Midwest',   'USA', 'Pittsburgh',   'Approved',  'Raw Materials',           'Net 60', 'Small',      'Frank Wilson',    'f.wilson@glsteel.com',      TRUE, DATE '2021-04-01'),
(18, 'BoxRight Packaging',         'SUP-018', 'Southeast', 'USA', 'Tampa',        'Approved',  'Packaging',               'Net 30', 'Small',      'Helen Carter',    'h.carter@boxright.com',     TRUE, DATE '2021-07-15'),
(19, 'RoadRunner Transport',       'SUP-019', 'Southwest', 'USA', 'Phoenix',      'Approved',  'Logistics & Freight',     'Net 30', 'Small',      'Steve Martinez',  's.martinez@roadrunner.com', TRUE, DATE '2021-09-01'),
(20, 'ToolMaster MRO',             'SUP-020', 'Midwest',   'USA', 'Milwaukee',    'Approved',  'MRO',                     'Net 30', 'Small',      'Anna Weber',      'a.weber@toolmaster.com',    TRUE, DATE '2021-11-15'),
(21, 'Vertex Engineering',         'SUP-021', 'Southeast', 'USA', 'Miami',        'Approved',  'Professional Services',   'Net 45', 'Medium',     'Chris Thompson',  'c.thompson@vertex.com',     TRUE, DATE '2022-01-10'),
(22, 'ClearPath IT Solutions',     'SUP-022', 'West',      'USA', 'Seattle',      'Approved',  'IT Hardware & Software',  'Net 30', 'Small',      'Lisa Chang',      'l.chang@clearpath.com',     TRUE, DATE '2022-03-01'),
(23, 'Keystone Facilities',        'SUP-023', 'Northeast', 'USA', 'Baltimore',    'Approved',  'Facilities & Utilities',  'Net 30', 'Small',      'Mark Evans',      'm.evans@keystone.com',      TRUE, DATE '2022-05-15'),
(24, 'Summit Chemical Works',      'SUP-024', 'Southeast', 'USA', 'Nashville',    'Approved',  'Chemicals & Consumables', 'Net 45', 'Small',      'Tina Roberts',    't.roberts@sumchem.com',     TRUE, DATE '2022-07-01'),
(25, 'Pacific Components Inc.',    'SUP-025', 'West',      'USA', 'Portland',     'Approved',  'Industrial Components',   'Net 60', 'Small',      'Gary Lee',        'g.lee@paccomponents.com',   TRUE, DATE '2022-08-15'),
(26, 'ProFreight Solutions',       'SUP-026', 'Midwest',   'USA', 'Kansas City',  'Approved',  'Logistics & Freight',     'Net 30', 'Small',      'Susan Hall',      's.hall@profreight.com',     TRUE, DATE '2022-10-01'),
(27, 'Lakeside Steel Co.',         'SUP-027', 'Midwest',   'USA', 'Toledo',       'Approved',  'Raw Materials',           'Net 60', 'Small',      'Brian Davis',     'b.davis@lakesidesteel.com', TRUE, DATE '2022-11-01'),
-- SPOT (3)
(28, 'Cascade Paper & Pack',       'SUP-028', 'West',      'USA', 'Portland',     'Spot',      'Packaging',               'Net 30', 'Small',      'Olivia White',    'o.white@cascade.com',       TRUE, DATE '2023-02-01'),
(29, 'Allied Temp Services',       'SUP-029', 'National',  'USA', 'Chicago',      'Spot',      'Professional Services',   'Net 30', 'Small',      'Paul Brown',      'p.brown@alliedtemp.com',    TRUE, DATE '2023-05-15'),
(30, 'Delta Equipment Co.',        'SUP-030', 'Southeast', 'USA', 'Atlanta',      'Spot',      'Capital Equipment',       'Net 60', 'Medium',     'Nicole Adams',    'n.adams@deltaequip.com',    TRUE, DATE '2023-09-01');


-- ============================================================
-- 6. fact_purchase_orders
--
-- Grain:
-- One row per purchase order.
--
-- Generates approximately 4,800 purchase orders with realistic
-- procurement attributes including supplier, category, payment
-- status, delivery performance, and spend amount.
-- ============================================================
-- Supplier tier share:  Strategic 50% | Preferred 33% | Approved 13% | Spot 4%
-- On-time delivery:     Strategic 90% | Preferred 82% | Approved  72% | Spot 58%
-- All randomness uses hash() — deterministic and reproducible.
-- ============================================================
INSERT INTO fact_purchase_orders
WITH
-- Probability slots 0-99 mapped to supplier_id
sup_slots(sid, lo, hi) AS (
    VALUES
        (1,0,10),(2,10,20),(3,20,30),(4,30,40),(5,40,50),
        (6,50,53),(7,53,56),(8,56,59),(9,59,62),(10,62,65),
        (11,65,68),(12,68,71),(13,71,74),(14,74,77),(15,77,80),(16,80,83),
        (17,83,85),(18,85,86),(19,86,87),(20,87,88),(21,88,89),
        (22,89,90),(23,90,91),(24,91,92),(25,92,93),(26,93,94),(27,94,96),
        (28,96,97),(29,97,98),(30,98,100)
),
-- Primary category per supplier
sup_cat(sid, cid) AS (
    VALUES
        (1,1),(2,2),(3,5),(4,3),(5,7),(6,1),(7,4),(8,2),(9,5),(10,6),
        (11,8),(12,9),(13,7),(14,3),(15,4),(16,5),(17,1),(18,2),(19,5),
        (20,6),(21,8),(22,7),(23,9),(24,4),(25,3),(26,5),(27,1),(28,2),(29,8),(30,10)
),
nums AS (SELECT unnest(generate_series(1, 4800)) AS n),
-- All hash seeds in one pass (different prime offsets keep fields independent)
h AS (
    SELECT n,
        (hash(n::BIGINT)           % 100)::INTEGER   AS rs,
        (hash(n::BIGINT + 1000003) % 1096)::INTEGER  AS rd,
        (hash(n::BIGINT + 2000003) % 100)::INTEGER   AS rp,
        (hash(n::BIGINT + 3000003) % 100)::INTEGER   AS rq,
        (hash(n::BIGINT + 4000003) % 100)::INTEGER   AS rl,
        (hash(n::BIGINT + 4500003) % 28)::INTEGER    AS rm,
        (hash(n::BIGINT + 5000003) % 100)::INTEGER   AS rb,
        (hash(n::BIGINT + 6000003) % 100)::INTEGER   AS ro,
        (hash(n::BIGINT + 7000003) % 500000)::BIGINT AS ra,
        (hash(n::BIGINT + 8000003) % 32)::INTEGER    AS rld
    FROM nums
),
base AS (
    SELECT h.*, ss.sid AS supplier_id, sc.cid AS category_id
    FROM h
    JOIN sup_slots ss ON h.rs >= ss.lo AND h.rs < ss.hi
    JOIN sup_cat   sc ON ss.sid = sc.sid
),
po AS (
    SELECT
        n, supplier_id, category_id, rq, rl, rm, rld,
        -- PO date: uniform across 1,096 days in range 2022–2024
        (DATE '2022-01-01' + CAST(rd AS INTEGER))                                           AS po_date,
        CAST(strftime('%Y%m%d', DATE '2022-01-01' + CAST(rd AS INTEGER)) AS INTEGER)        AS date_id,

        -- Business unit driven by category with ~20% variance
        CASE category_id
            WHEN 1  THEN CASE WHEN rb<80 THEN 1 ELSE 2 END
            WHEN 2  THEN 1
            WHEN 3  THEN CASE WHEN rb<70 THEN 1 ELSE 6 END
            WHEN 4  THEN CASE WHEN rb<55 THEN 6 ELSE 1 END
            WHEN 5  THEN CASE WHEN rb<70 THEN 2 ELSE 3 END
            WHEN 6  THEN 3
            WHEN 7  THEN 5
            WHEN 8  THEN CASE WHEN rb<55 THEN 8 ELSE 4 END
            WHEN 9  THEN CASE WHEN rb<75 THEN 3 ELSE 8 END
            WHEN 10 THEN 1  ELSE 1
        END AS bu_id,

        -- Location driven by category and purchase type
        CASE
            WHEN category_id = 7                     THEN 1
            WHEN category_id = 8 AND ro < 65         THEN 1
            WHEN category_id = 8                     THEN CASE WHEN ro%3=0 THEN 2 WHEN ro%3=1 THEN 3 ELSE 4 END
            WHEN category_id IN (1,2,3,10) AND ro<60 THEN 2
            WHEN category_id IN (1,2,3,10)           THEN 3
            WHEN category_id = 4                     THEN 6
            WHEN category_id = 5                     THEN 1 + (ro % 5)
            WHEN category_id IN (6,9)                THEN CASE WHEN ro%4=0 THEN 2 WHEN ro%4=1 THEN 3 WHEN ro%4=2 THEN 4 ELSE 1 END
            ELSE CASE WHEN ro<30 THEN 1 WHEN ro<60 THEN 2 WHEN ro<80 THEN 3 ELSE 4 END
        END AS loc_id,

        -- Amount by category, rounded to nearest $100
        ROUND(CAST(CASE category_id
            WHEN 1  THEN  5000 + ra % 245000
            WHEN 2  THEN  1500 + ra %  98500
            WHEN 3  THEN  3000 + ra % 147000
            WHEN 4  THEN  1000 + ra %  74000
            WHEN 5  THEN   500 + ra %  49500
            WHEN 6  THEN   150 + ra %  14850
            WHEN 7  THEN  1500 + ra %  98500
            WHEN 8  THEN  2000 + ra % 148000
            WHEN 9  THEN   300 + ra %  29700
            WHEN 10 THEN 15000 + ra % 285000
            ELSE          5000 + ra %  95000
        END AS DECIMAL), -2) AS total_amount,

        -- Quantity by category
        CAST(CASE category_id
            WHEN 1  THEN  10 + ra %  490
            WHEN 2  THEN  50 + ra % 1950
            WHEN 3  THEN   5 + ra %  195
            WHEN 4  THEN 100 + ra % 4900
            WHEN 5  THEN   1 + ra %   49
            WHEN 6  THEN   1 + ra %   99
            WHEN 7  THEN   1 + ra %   49
            WHEN 8  THEN   1 + ra %   11
            WHEN 9  THEN   1 + ra %   11
            WHEN 10 THEN   1 + ra %    4
            ELSE    1
        END AS DECIMAL) AS qty,

        -- PO status
        CASE
            WHEN rp < 55 THEN 'Closed'
            WHEN rp < 80 THEN 'Approved'
            WHEN rp < 90 THEN 'Pending'
            WHEN rp < 97 THEN 'Rejected'
            ELSE              'Cancelled'
        END AS po_status,

        -- Days late by supplier tier (NULL for Rejected/Cancelled/Pending)
        CASE
            WHEN rp >= 90 THEN NULL
            WHEN rp >= 80 THEN NULL
            WHEN supplier_id <=  5 THEN CASE WHEN rl<90 THEN 0 WHEN rl<97 THEN rm%7+1  ELSE rm%14+7  END
            WHEN supplier_id <= 16 THEN CASE WHEN rl<82 THEN 0 WHEN rl<93 THEN rm%10+1 ELSE rm%21+10 END
            WHEN supplier_id <= 27 THEN CASE WHEN rl<72 THEN 0 WHEN rl<88 THEN rm%14+1 ELSE rm%28+14 END
            ELSE                        CASE WHEN rl<58 THEN 0 WHEN rl<80 THEN rm%15+1 ELSE rm%30+15 END
        END AS days_late
    FROM base
)
SELECT
    n                                                                   AS po_id,
    'PO-' || lpad(n::VARCHAR, 5, '0')                                  AS po_number,
    date_id,
    supplier_id,
    category_id,
    bu_id                                                               AS business_unit_id,
    loc_id                                                              AS location_id,
    qty                                                                 AS quantity,
    ROUND(total_amount / qty, 4)                                        AS unit_price,
    total_amount,
    'USD'                                                               AS currency,
    po_status,
    CASE
        WHEN po_status IN ('Rejected','Cancelled') THEN NULL
        WHEN po_status = 'Pending'                 THEN 'Outstanding'
        WHEN rq < 70                               THEN 'Paid'
        WHEN rq < 85                               THEN 'Outstanding'
        WHEN rq < 95                               THEN 'Overdue'
        ELSE                                            'Disputed'
    END                                                                 AS payment_status,
    CASE WHEN po_status IN ('Rejected','Cancelled')
         THEN NULL
         ELSE (po_date + 14 + rld)
    END                                                                 AS expected_delivery,
    CASE WHEN days_late IS NULL
         THEN NULL
         ELSE (po_date + 14 + rld + days_late)
    END                                                                 AS actual_delivery,
    days_late,
    CASE WHEN po_status IN ('Rejected','Cancelled')
         THEN NULL
         ELSE 'INV-' || lpad(n::VARCHAR, 5, '0')
    END                                                                 AS invoice_number,
    NULL::VARCHAR                                                       AS notes
FROM po;


-- ============================================================
-- 7. fact_supplier_performance  — monthly KPIs per supplier
--
-- Grain:
-- One row per supplier per month.
--
-- Generates monthly KPI snapshots used for supplier scorecards,
-- trend analysis, and composite risk modeling.
-- ============================================================
-- Covers every month from each supplier's onboarding date.
-- Suppliers 20, 24, 26 have declining OTD rate over time
-- (intentional story for trend analysis in Phase 6/7).
-- ============================================================
INSERT INTO fact_supplier_performance
WITH
months AS (
    SELECT i, make_date(CAST(2022 + floor(i/12) AS BIGINT), CAST((i % 12) + 1 AS BIGINT), CAST(1 AS BIGINT)) AS month_start
    FROM (SELECT unnest(generate_series(0, 35)) AS i)
),
month_dates AS (
    SELECT m.i, m.month_start, d.date_id
    FROM months m
    JOIN dim_date d ON d.full_date = m.month_start
),
sm AS (
    SELECT
        row_number() OVER (ORDER BY s.supplier_id, md.i)   AS perf_id,
        s.supplier_id,
        s.supplier_tier,
        md.date_id,
        md.i                                               AS mth,
        (hash((s.supplier_id * 100 + md.i)::BIGINT)           % 100)::INTEGER   AS h1,
        (hash((s.supplier_id * 100 + md.i + 10000)::BIGINT)   % 100)::INTEGER   AS h2,
        (hash((s.supplier_id * 100 + md.i + 20000)::BIGINT)   % 1000)::INTEGER  AS h3
    FROM dim_suppliers s
    CROSS JOIN month_dates md
    WHERE s.is_active = TRUE
      AND md.month_start >= date_trunc('month', s.onboarding_date)
),
computed AS (
    SELECT *,
        CAST(CASE supplier_tier
            WHEN 'Strategic' THEN  8 + h1 % 18
            WHEN 'Preferred' THEN  4 + h1 % 12
            WHEN 'Approved'  THEN  2 + h1 %  8
            ELSE                   1 + h1 %  3
        END AS INTEGER) AS tot,

        -- OTD rate; suppliers 20/24/26 decline 0.4 pp per month
        LEAST(100.0, GREATEST(0.0, ROUND(CAST(
            CASE supplier_tier
                WHEN 'Strategic' THEN 90.0 + h2 % 10
                WHEN 'Preferred' THEN 80.0 + h2 % 15
                WHEN 'Approved'  THEN 68.0 + h2 % 20
                ELSE                  50.0 + h2 % 30
            END
            - CASE WHEN supplier_id IN (20, 24, 26) THEN mth * 0.4 ELSE 0.0 END
        AS DECIMAL), 1))) AS otd,

        LEAST(15.0, GREATEST(0.0, ROUND(CAST(CASE supplier_tier
            WHEN 'Strategic' THEN 0.1 + (h3 %  15) * 0.1
            WHEN 'Preferred' THEN 0.5 + (h3 %  30) * 0.1
            WHEN 'Approved'  THEN 1.5 + (h3 %  55) * 0.1
            ELSE                  3.0 + (h3 %  80) * 0.1
        END AS DECIMAL), 1))) AS def_r,

        ROUND(CAST(CASE supplier_tier
            WHEN 'Strategic' THEN 10.0 + (h3 % 140) * 0.1
            WHEN 'Preferred' THEN 14.0 + (h3 % 200) * 0.1
            WHEN 'Approved'  THEN 18.0 + (h3 % 200) * 0.1
            ELSE                  21.0 + (h3 % 300) * 0.1
        END AS DECIMAL), 1) AS lead,

        LEAST(10.0, GREATEST(1.0, ROUND(CAST(CASE supplier_tier
            WHEN 'Strategic' THEN 1.0 + (h2 % 30) * 0.1
            WHEN 'Preferred' THEN 2.0 + (h2 % 40) * 0.1
            WHEN 'Approved'  THEN 4.0 + (h2 % 40) * 0.1
            ELSE                  5.5 + (h2 % 45) * 0.1
        END AS DECIMAL), 1))) AS risk,

        LEAST(10.0, GREATEST(1.0, ROUND(CAST(CASE supplier_tier
            WHEN 'Strategic' THEN 7.5 + (h1 % 25) * 0.1
            WHEN 'Preferred' THEN 5.5 + (h1 % 30) * 0.1
            WHEN 'Approved'  THEN 3.5 + (h1 % 35) * 0.1
            ELSE                  2.0 + (h1 % 40) * 0.1
        END AS DECIMAL), 1))) AS perf
    FROM sm
)
SELECT
    CAST(perf_id AS INTEGER)                                             AS performance_id,
    supplier_id,
    date_id,
    tot                                                                  AS total_orders,
    GREATEST(0, CAST(ROUND(tot * otd / 100.0) AS INTEGER))              AS on_time_orders,
    tot - GREATEST(0, CAST(ROUND(tot * otd / 100.0) AS INTEGER))        AS late_orders,
    GREATEST(0, CAST(ROUND(tot * def_r / 100.0) AS INTEGER))            AS defective_orders,
    otd                                                                  AS on_time_delivery_rate,
    def_r                                                                AS defect_rate,
    LEAST(100.0, GREATEST(85.0, ROUND(100.0 - def_r * 1.5, 1)))        AS order_accuracy_rate,
    lead                                                                 AS avg_lead_time_days,
    NULL::DECIMAL                                                        AS total_spend,
    risk                                                                 AS risk_score,
    perf                                                                 AS performance_score
FROM computed
ORDER BY supplier_id, date_id;


-- ============================================================
-- 8. VERIFICATION  — run after to confirm all counts
-- Uncomment to confirm successful data generation.
-- ============================================================
SELECT 'dim_date'                  AS tbl, COUNT(*) AS rows FROM dim_date                  UNION ALL
SELECT 'dim_locations',                    COUNT(*)          FROM dim_locations             UNION ALL
SELECT 'dim_categories',                   COUNT(*)          FROM dim_categories            UNION ALL
SELECT 'dim_business_units',               COUNT(*)          FROM dim_business_units        UNION ALL
SELECT 'dim_suppliers',                    COUNT(*)          FROM dim_suppliers             UNION ALL
SELECT 'fact_purchase_orders',             COUNT(*)          FROM fact_purchase_orders      UNION ALL
SELECT 'fact_supplier_performance',        COUNT(*)          FROM fact_supplier_performance
ORDER BY tbl;
