# 34 - Shopify API vs CSV Order Reconciliation

## Summary

This milestone added a reconciliation layer comparing Shopify Admin API order and line item landing data against the existing CSV-derived order warehouse.

The goal was to understand how closely recent API-derived orders match the current CSV-derived `staging` and `marts` order models before making any canonical raw rebuild changes.

The milestone succeeded.

## What changed

Added an analysis view:

```text
sql/analysis/shopify_api_csv_order_reconciliation.sql
```

This creates:

```text
marts.anl_shopify_api_csv_order_reconciliation
```

The view compares recent API-accessible orders across:

```text
raw_load.shopify_orders_api_latest
raw_load.shopify_order_line_items_api_latest
staging.stg_shopify_orders
staging.stg_shopify_order_items
marts.fct_orders
```

Added a validation query:

```text
sql/validation/shopify_api_csv_order_reconciliation_validation.sql
```

The validation query checks:

- reconciliation row count
- duplicate unified order numbers
- API-only order rows
- staging-only order rows in the API-accessible window
- matched API/staging/fct order rows
- order total comparison
- line item count comparison
- total item quantity comparison
- financial status comparison
- fulfillment status comparison

## Validation results

Key final validation results:

```text
reconciliation_view_row_count              629  PASS
duplicate_unified_order_numbers            0    PASS
api_order_rows                             626  INFO
fct_order_rows_in_api_window               581  INFO
api_only_order_rows                        48   REVIEW
api_only_orders_newer_than_staging_max     48   INFO
staging_only_order_rows_in_api_window      3    REVIEW
order_total_differs_from_staging_rows      2    REVIEW
line_item_count_differs_from_staging_rows  0    PASS
total_items_differs_from_staging_rows      0    PASS
financial_status_differs_from_staging      3    REVIEW
fulfillment_status_differs_from_staging    75   REVIEW
```

## Review findings

The reconciliation is structurally strong:

- no duplicate unified order numbers
- API line item counts match staging for matched orders
- API total item quantities match staging for matched orders
- API-only orders are explained by newer orders created after the latest CSV export

The 48 API-only orders were reviewed and found to be new orders from April 22 through April 30.

The remaining review rows are not blockers for this milestone:

- `staging_only_order_rows_in_api_window = 3` is a small edge case to keep visible
- `order_total_differs_from_staging_rows = 2` should be reviewed before canonical rebuild planning
- `financial_status_differs_from_staging = 3` is minor
- `fulfillment_status_differs_from_staging = 75` is likely due to current API state vs older CSV snapshot/status timing

## Design decisions

This milestone is comparison-only.

It intentionally does not:

- replace Shopify CSV ingestion
- modify canonical `raw.shopify_orders`
- modify `staging.stg_shopify_orders`
- modify `staging.stg_shopify_order_items`
- modify `marts.fct_orders`
- modify `marts.fct_order_items`
- modify business-facing analysis models
- schedule API ingestion
- use API order data as the warehouse source of truth

The existing CSV ingestion path remains the known-good historical baseline.

Current migration path:

```text
Shopify API -> isolated API landing tables -> API-vs-CSV reconciliation -> scheduled API landing -> eventual canonical raw rebuild
```

## Result

The project now has API-vs-CSV reconciliation coverage for:

- products
- product variants
- customers
- orders
- order line items

The recent API order data reconciles well enough against the CSV-derived warehouse to continue toward scheduled Shopify API landing.

## Next step

Recommended next milestone:

```text
35 - Scheduled Shopify API Landing MVP
```

Suggested goal:

```text
Schedule the isolated Shopify API landing DAGs for products, customers, and orders while preserving the CSV ingestion path as fallback.
```
