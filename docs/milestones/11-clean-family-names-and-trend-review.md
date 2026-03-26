# Milestone 11 - Clean Family Names and Trend Review

## Summary
This milestone improved consistency and readability in family-level analysis by fixing product family grain issues, propagating cleaned canonical family names into the trusted monthly family layer, and adding recent trend review queries for business-facing analysis.

## Why this mattered
During review of product family trend outputs, we found that some queries were returning multiple rows for the same `product_family_key`. Investigation showed that family-level analysis was still allowing multiple `product_family_name` values per family key, often due to lingering size/body suffixes in historical product names.

This caused two downstream problems:
- family-grain outputs were not always truly one row per family
- dirty names could leak into trusted monthly trend outputs and business-facing review queries

## What changed

### 1. Fixed family grain in `anl_product_performance_by_family`
Updated the family performance view so that it now:
- aggregates metrics strictly by `product_family_key`
- selects one canonical `product_family_name` per family key after aggregation
- strips lingering size/body-related suffixes from names while preserving color information

### 2. Cleaned canonical names in the trusted monthly family layer
Updated `anl_product_revenue_monthly_by_family_trusted_dates` so that it now:
- keeps the existing trusted-date filtering logic
- keeps the existing family-key rollup logic
- sources canonical cleaned `product_family_name` values from `anl_product_performance_by_family`

This prevents dirty historical names from propagating into monthly family trend outputs.

### 3. Added recent family trend model
Added `anl_product_family_recent_trends_trusted`, a family-level trend view that:
- compares the last 3 trusted months to the prior 3 trusted months
- includes recent revenue and unit changes
- tracks months with sales in each comparison window
- adds `lifetime_months_with_sales` for longer-term family context

### 4. Added business-facing trend review queries
Added `product_family_recent_trends_review.sql`, including queries for:
- top rising core apparel families
- top declining core apparel families
- new or returning families
- top lifetime performers still rising
- variant drill-down for selected candidate families

The review queries also exclude obvious non-core items like mystery boxes and bundles.

## Validation
Validated that:
- `anl_product_performance_by_family` returns one row per `product_family_key`
- `anl_product_revenue_monthly_by_family_trusted_dates` returns one row per `order_month` + `product_family_key`
- previously problematic families such as `ts-dag-ra`, `ts-lad-ra`, and `ts-tw-ri` now show cleaner canonical family names
- recent trend review queries return cleaner and more interpretable outputs

## Files added / updated
- `sql/analysis/product_performance_by_family.sql`
- `sql/analysis/product_revenue_monthly_by_family_trusted_dates.sql`
- `sql/analysis/product_family_recent_trends_trusted.sql`
- `sql/analysis/product_family_recent_trends_review.sql`
- `sql/validation/product_revenue_monthly_by_family_trusted_dates_validation.sql`

## Business impact
This milestone makes family-level trend analysis more trustworthy and easier to interpret. It improves conversations around:
- which long-running products are still growing
- which newer products are gaining traction
- which families are cooling off
- which specific variants are driving movement inside important product families

It also strengthens the portfolio story by showing careful debugging of grain issues, canonical naming cleanup, and layered semantic analysis on top of trusted marts.
