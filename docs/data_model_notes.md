# Procurement Spend Intelligence Platform

## Fact Tables

### fact_purchase_orders

Purpose:
Stores one row per purchase order transaction.

### fact_supplier_performance

Purpose:
Stores monthly supplier performance metrics.

---

## Dimension Tables

### dim_date

Purpose:
Stores calendar information.

### dim_suppliers

Purpose:
Stores supplier information.

### dim_categories

Purpose:
Stores procurement category information.

### dim_business_units

Purpose:
Stores department information.

### dim_locations

Purpose:
Stores company location information.

---

## Star Schema

Central Fact Table:
fact_purchase_orders

Connected Dimensions:
- dim_date
- dim_suppliers
- dim_categories
- dim_business_units
- dim_locations