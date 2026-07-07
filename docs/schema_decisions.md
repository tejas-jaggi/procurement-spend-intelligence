# Schema Design Decisions

## Why a Star Schema?

The project uses a star schema because it is commonly used in data warehouses and business intelligence systems.

Benefits:

- Faster analytics queries
- Easier Power BI integration
- Simpler reporting
- Clear separation of facts and dimensions

---

## Why fact_purchase_orders is the Central Table

All procurement transactions flow through purchase orders.

This table stores:

- Quantity
- Unit Price
- Total Spend
- Delivery Information

Every major business analysis starts from this table.

---

## Why Separate Supplier Performance Exists

Supplier performance is tracked monthly and may include metrics not directly available from purchase order transactions.

Keeping it separate allows:

- Risk Analysis
- Supplier Scorecards
- KPI Dashboards

---

## Why Use Integer Date Keys

date_id is stored as YYYYMMDD.

Benefits:

- Faster joins
- Faster filtering
- Common data warehouse practice

Example:

20240115

represents

January 15, 2024

---

## Why Use DECIMAL for Money

Financial values should use DECIMAL rather than FLOAT to avoid rounding errors.