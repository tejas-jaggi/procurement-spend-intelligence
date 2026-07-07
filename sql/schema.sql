-- ============================================================
-- PROCUREMENT SPEND INTELLIGENCE PLATFORM
-- ============================================================
-- File:    schema.sql
-- Phase   : 2–3 (Schema Design & Database Creation)
-- Purpose: Create the star schema, constraints, and indexes
-- DB:      DuckDB 1.5.x
-- ============================================================
-- Execution order:
--   1. schema.sql
--   2. data_generation.sql
--   3. validation.sql
--   4. spend_analysis.sql
--   5. phase7_advanced_analytics.sql
-- ============================================================


-- ============================================================
-- CLEANUP
-- Drop existing tables (fact tables first) so the script
-- can be executed repeatedly without manual cleanup.
-- ============================================================
DROP TABLE IF EXISTS fact_supplier_performance;
DROP TABLE IF EXISTS fact_purchase_orders;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS dim_suppliers;
DROP TABLE IF EXISTS dim_categories;
DROP TABLE IF EXISTS dim_business_units;
DROP TABLE IF EXISTS dim_locations;


-- ============================================================
-- DIMENSION TABLES
-- ============================================================

-- ------------------------------------------------------------
-- dim_date
-- One row per calendar day covering 2022–2024.
-- date_id is stored as YYYYMMDD integer (e.g. 20230115).
-- Integer surrogate keys are a common data warehouse design
-- because they simplify joins, partitioning, and date-range
-- filtering while remaining easy to read.
-- ------------------------------------------------------------
CREATE TABLE dim_date (
    date_id        INTEGER      PRIMARY KEY,
    full_date      DATE         NOT NULL UNIQUE,
    year           INTEGER      NOT NULL,
    quarter        INTEGER      NOT NULL,           -- 1 through 4
    quarter_label  VARCHAR(10),                     -- 'Q1 2023'
    month          INTEGER      NOT NULL,           -- 1 through 12
    month_name     VARCHAR(20),                     -- 'January'
    month_label    VARCHAR(10),                     -- 'Jan-23'
    week           INTEGER,
    day_of_week    INTEGER,                         -- 1=Monday, 7=Sunday
    day_name       VARCHAR(20),
    is_weekday     BOOLEAN,
    fiscal_year    INTEGER,
    fiscal_quarter INTEGER
);


-- ------------------------------------------------------------
-- dim_suppliers
-- Master vendor registry. supplier_tier drives segmentation
-- logic across spend analysis, risk scoring, and savings
-- opportunity identification.
-- ------------------------------------------------------------
CREATE TABLE dim_suppliers (
    supplier_id     INTEGER       PRIMARY KEY,
    supplier_name   VARCHAR(100)  NOT NULL,
    supplier_code   VARCHAR(20)   NOT NULL UNIQUE,  -- 'SUP-001'
    region          VARCHAR(50),                    -- 'Midwest', 'Southeast', 'Northeast', 'West', 'International'
    country         VARCHAR(50)   DEFAULT 'USA',
    city            VARCHAR(50),
    supplier_tier   VARCHAR(20)   CHECK (supplier_tier IN ('Strategic', 'Preferred', 'Approved', 'Spot')),
    category_focus  VARCHAR(100),                   -- Primary goods/services supplied
    payment_terms   VARCHAR(20)   CHECK (payment_terms IN ('Immediate','Net 15','Net 30','Net 45','Net 60','Net 90')),
    company_size    VARCHAR(20)   CHECK (company_size IN ('Small', 'Medium', 'Large', 'Enterprise')),
    contact_name    VARCHAR(100),
    contact_email   VARCHAR(100),
    is_active       BOOLEAN       DEFAULT TRUE,
    onboarding_date DATE
);


-- ------------------------------------------------------------
-- dim_categories
-- Two-level taxonomy: category_group (Direct / Indirect)
-- then category_name.
-- Direct = production materials that go into the final product.
-- Indirect = operational purchases (IT, facilities, services).
-- ------------------------------------------------------------
CREATE TABLE dim_categories (
    category_id    INTEGER       PRIMARY KEY,
    category_name  VARCHAR(100)  NOT NULL,
    category_group VARCHAR(20)   CHECK (category_group IN ('Direct', 'Indirect')),
    category_code  VARCHAR(20)   UNIQUE,            -- 'CAT-RM'
    subcategory    VARCHAR(100),
    description    VARCHAR(255),
    annual_budget  DECIMAL(15,2)
);


-- ------------------------------------------------------------
-- dim_business_units
-- Internal departments that raise and approve purchase orders.
-- Supports spend-by-department analysis and budget vs actual.
-- ------------------------------------------------------------
CREATE TABLE dim_business_units (
    business_unit_id   INTEGER       PRIMARY KEY,
    business_unit_name VARCHAR(100)  NOT NULL,
    bu_code            VARCHAR(20)   UNIQUE,        -- 'BU-MFG'
    department         VARCHAR(100),
    cost_center        VARCHAR(50),
    manager_name       VARCHAR(100),
    annual_budget      DECIMAL(15,2),
    region             VARCHAR(50)
);


-- ------------------------------------------------------------
-- dim_locations
-- Company facility locations. Supports spend and supplier-risk analysis
-- broken down by plant, warehouse, or office.
-- ------------------------------------------------------------
CREATE TABLE dim_locations (
    location_id   INTEGER       PRIMARY KEY,
    location_name VARCHAR(100)  NOT NULL,
    city          VARCHAR(50),
    state         VARCHAR(50),
    country       VARCHAR(50)   DEFAULT 'USA',
    region        VARCHAR(50),
    location_type VARCHAR(50)   CHECK (location_type IN ('HQ', 'Plant', 'Warehouse', 'Distribution Center', 'Office'))
);


-- ============================================================
-- FACT TABLES
-- ============================================================

-- ------------------------------------------------------------
-- fact_purchase_orders
-- Core transaction table — one row per purchase order.
-- This is the center of the star schema; all 5 dimension
-- tables connect here via foreign keys.
--
-- days_late is pre-computed (actual_delivery - expected_delivery)
-- and stored as a signed integer for fast aggregation:
--   Positive = arrived late
--   Zero     = arrived exactly on time
--   Negative = arrived early
-- ------------------------------------------------------------
CREATE TABLE fact_purchase_orders (
    po_id             INTEGER       PRIMARY KEY,
    po_number         VARCHAR(20)   NOT NULL UNIQUE,   -- 'PO-2023-00001'
    date_id           INTEGER       REFERENCES dim_date(date_id),
    supplier_id       INTEGER       REFERENCES dim_suppliers(supplier_id),
    category_id       INTEGER       REFERENCES dim_categories(category_id),
    business_unit_id  INTEGER       REFERENCES dim_business_units(business_unit_id),
    location_id       INTEGER       REFERENCES dim_locations(location_id),
    quantity          DECIMAL(10,2),
    unit_price        DECIMAL(15,4),
    total_amount      DECIMAL(15,2)  NOT NULL,
    currency          VARCHAR(5)     DEFAULT 'USD',
    po_status         VARCHAR(20)    CHECK (po_status IN ('Approved', 'Pending', 'Rejected', 'Closed', 'Cancelled')),
    payment_status    VARCHAR(20)    CHECK (payment_status IN ('Paid', 'Outstanding', 'Overdue', 'Disputed')),
    expected_delivery DATE,
    actual_delivery   DATE,
    days_late         INTEGER,
    invoice_number    VARCHAR(50),
    notes             VARCHAR(500)
);


-- ------------------------------------------------------------
-- fact_supplier_performance
-- Monthly supplier KPI snapshot — one row per supplier per
-- month. Decoupled from fact_purchase_orders intentionally:
-- performance metrics are aggregated and scored externally
-- (e.g. by procurement team), not derived purely from PO data.
--
-- risk_score:        1 (low risk) to 10 (critical risk)
-- performance_score: 1 (poor)     to 10 (excellent)
-- UNIQUE constraint prevents duplicate months per supplier.
-- ------------------------------------------------------------
CREATE TABLE fact_supplier_performance (
    performance_id        INTEGER       PRIMARY KEY,
    supplier_id           INTEGER       REFERENCES dim_suppliers(supplier_id),
    date_id               INTEGER       REFERENCES dim_date(date_id),  -- First calendar day of the month
    total_orders          INTEGER,
    on_time_orders        INTEGER,
    late_orders           INTEGER,
    defective_orders      INTEGER,
    on_time_delivery_rate DECIMAL(5,2),   -- 0.00 to 100.00
    defect_rate           DECIMAL(5,2),   -- 0.00 to 100.00
    order_accuracy_rate   DECIMAL(5,2),   -- 0.00 to 100.00
    avg_lead_time_days    DECIMAL(5,1),
    total_spend           DECIMAL(15,2),
    risk_score            DECIMAL(4,1)    CHECK (risk_score BETWEEN 1.0 AND 10.0),
    performance_score     DECIMAL(4,1)    CHECK (performance_score BETWEEN 1.0 AND 10.0),
    CONSTRAINT uq_supplier_month UNIQUE (supplier_id, date_id)
);


-- ============================================================
-- INDEXES
-- Optimized for the most common analytical query patterns:
-- date filtering, supplier analysis, category reporting,
-- payment status, and supplier performance.
-- ============================================================

CREATE INDEX idx_po_date_id        ON fact_purchase_orders (date_id);
CREATE INDEX idx_po_supplier_id    ON fact_purchase_orders (supplier_id);
CREATE INDEX idx_po_category_id    ON fact_purchase_orders (category_id);
CREATE INDEX idx_po_bu_id          ON fact_purchase_orders (business_unit_id);
CREATE INDEX idx_po_location_id    ON fact_purchase_orders (location_id);
CREATE INDEX idx_po_status         ON fact_purchase_orders (po_status);
CREATE INDEX idx_po_payment_status ON fact_purchase_orders (payment_status);

CREATE INDEX idx_perf_supplier_id  ON fact_supplier_performance (supplier_id);
CREATE INDEX idx_perf_date_id      ON fact_supplier_performance (date_id);
CREATE INDEX idx_perf_risk         ON fact_supplier_performance (risk_score);


-- ============================================================
-- VERIFICATION
-- Optional verification.
-- Uncomment to confirm that all tables were created successfully.
-- ============================================================
-- SELECT table_name
-- FROM information_schema.tables
-- WHERE table_schema = 'main'
-- ORDER BY table_name;
