# 32 - Shopify API vs CSV Customer Reconciliation

## Summary

This milestone added a reconciliation layer comparing Shopify Admin API customer landing data against the existing CSV-derived customer warehouse.

The goal was to understand how closely API-derived customers match the current CSV-derived `raw`, `staging`, and `dim_customers` models before making any canonical raw rebuild changes.

The milestone succeeded.

## What changed

Added an analysis view:

```text
sql/analysis/shopify_api_csv_customer_reconciliation.sql
```

This creates:

```text
marts.anl_shopify_api_csv_customer_reconciliation
```

The view compares customer records across:

```text
raw_load.shopify_customers_api_latest
raw.shopify_customers
staging.stg_shopify_customers
marts.dim_customers
```

Added a validation query:

```text
sql/validation/shopify_api_csv_customer_reconciliation_validation.sql
```

The validation query checks:

- reconciliation row count
- duplicate unified Shopify customer IDs
- API-only customer rows
- staging-only customer rows
- customers missing email
- matched customers by Shopify legacy customer ID
- email comparison
- order count comparison
- amount spent comparison
- tax-exempt comparison

## Validation results

Key final validation results:

```text
reconciliation_view_row_count             21463  PASS
duplicate_unified_shopify_customer_ids    0      PASS
matched_by_legacy_rows                    21388  INFO
api_customer_rows                         21462  INFO
staging_customer_rows                     21389  INFO
dim_customer_rows                         20574  INFO
api_customers_missing_email               816    REVIEW
api_only_customer_rows                    74     REVIEW
staging_only_customer_rows                1      REVIEW
amount_spent_differs_from_staging_rows    155    REVIEW
total_orders_differs_from_staging_rows    71     REVIEW
tax_exempt_differs_from_staging_rows      0      PASS
```

## Review findings

The reconciliation is structurally strong:

- no duplicate unified Shopify customer IDs
- strong API-to-staging overlap by Shopify legacy customer ID
- only one staging customer missing from API
- tax-exempt values reconcile after normalizing API `true` / `false` against staging `yes` / `no`

Remaining review items are not blockers for this milestone.

`api_customers_missing_email = 816` matters because the current warehouse uses `customer_email` as the practical customer key. These records should remain visible in future modeling work, but they can still be identified by Shopify customer ID.

`api_only_customer_rows = 74` is likely expected because the API pull may be newer than the CSV export.

`staging_only_customer_rows = 1` is small enough to review later as an edge case.

`amount_spent_differs_from_staging_rows = 155` and `total_orders_differs_from_staging_rows = 71` are plausible snapshot-timing differences between the API pull and CSV export.

## Design decisions

This milestone is comparison-only.

It intentionally does not:

- replace Shopify CSV ingestion
- modify canonical `raw.shopify_customers`
- modify `staging.stg_shopify_customers`
- modify `marts.dim_customers`
- modify customer analysis models
- schedule API ingestion
- use API customer data as the warehouse source of truth

The CSV ingestion path remains the known-good fallback.

Current migration path:

```text
Shopify API -> isolated API landing tables -> API-vs-CSV reconciliation -> eventual canonical raw rebuild
```

## Result

The project now has customer API-vs-CSV reconciliation coverage.

The API customer landing table is compatible enough with the existing CSV-derived warehouse to continue toward broader Shopify API ingestion, while keeping the CSV path intact.

## Next step

Recommended next milestone:

```text
33 - Shopify Orders API Landing MVP
```

Suggested goal:

```text
Land Shopify API order data into isolated raw_load tables without modifying canonical raw orders or downstream warehouse logic.
```
