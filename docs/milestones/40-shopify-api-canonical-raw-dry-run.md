# 40 - Shopify API Canonical Raw Rebuild Dry Run

## Summary

This milestone created an isolated dry run of the future Shopify API canonical raw rebuild path.

The goal was to simulate what would happen if the hybrid raw candidate tables were treated as canonical raw inputs for staging, without replacing production `raw`, production `staging`, marts, analysis models, or Airflow behavior.

## What changed

Added hybrid dry-run staging SQL:

```text
sql/staging/create_stg_shopify_products_hybrid_dry_run.sql
sql/staging/create_stg_shopify_customers_hybrid_dry_run.sql
sql/staging/create_stg_shopify_order_items_hybrid_dry_run.sql
sql/staging/create_stg_shopify_orders_hybrid_dry_run.sql
```

Added dry-run validation SQL:

```text
sql/validation/shopify_canonical_raw_dry_run_validation.sql
```

Created isolated dry-run staging tables in `raw_load`:

```text
raw_load.stg_shopify_products_hybrid_dry_run
raw_load.stg_shopify_customers_hybrid_dry_run
raw_load.stg_shopify_order_items_hybrid_dry_run
raw_load.stg_shopify_orders_hybrid_dry_run
```

## Design

The dry-run staging tables use the Milestone 39 hybrid raw candidate tables as inputs:

```text
raw_load.shopify_products_hybrid_raw_candidate
raw_load.shopify_customers_hybrid_raw_candidate
raw_load.shopify_orders_hybrid_raw_candidate
```

This simulates the staging impact of a future canonical raw replacement while keeping the test path isolated in `raw_load`.

The dry-run validation compares the hybrid dry-run staging outputs against current production staging contracts and key historical-preservation expectations.

## Non-goals

This milestone did not:

- Replace `raw.shopify_products`
- Replace `raw.shopify_customers`
- Replace `raw.shopify_orders`
- Modify production staging models
- Modify marts models
- Modify business-facing analysis models
- Add DAG or Airflow behavior
- Remove the CSV fallback path

## Validation

The validation query completed successfully.

No checks returned:

```text
FAIL
```

Validation status summary:

```text
PASS: 19
REVIEW: 2
INFO: 5
FAIL: 0
```

Key passing checks included:

```text
schema_contract_column_differences: 0
product_dry_run_current_staging_skus_missing: 0
customer_dry_run_current_staging_ids_missing: 0
customer_dry_run_duplicate_customer_ids: 0
order_item_dry_run_duplicate_line_item_fingerprints: 0
order_item_dry_run_missing_created_at_ts: 0
order_item_dry_run_missing_lineitem_price: 0
order_item_dry_run_missing_order_numbers: 0
order_item_dry_run_missing_quantity: 0
order_dry_run_api_forward_orders_included: 0
order_dry_run_current_orders_missing_before_cutover: 0
order_dry_run_duplicate_order_numbers: 0
order_dry_run_line_item_count_differences_before_cutover: 0
order_dry_run_order_total_differences_before_cutover: 0
order_dry_run_total_item_differences_before_cutover: 0
```

Important row counts and informational results included:

```text
product_dry_run_rows: 2204
customer_dry_run_rows: 21468
order_item_dry_run_rows: 48573
order_dry_run_rows: 23864
customer_dry_run_missing_email_rows: 817
order_dry_run_api_cutover_date: 2026-04-23
order_dry_run_api_forward_order_count: 46
order_dry_run_orders_not_in_current_staging: 46
product_dry_run_duplicate_nonblank_sku_keys: 0
```

Expected review items:

```text
customer_dry_run_lifetime_metric_differences_on_overlap: 156
product_dry_run_price_differences_on_overlap: 12
```

These review items are consistent with known API-vs-CSV source freshness differences.

## Result

Milestone 40 successfully proved that the Shopify hybrid raw candidate tables can feed staging-compatible dry-run outputs.

The dry run preserved current historical staging expectations before the API cutover date, included API-forward orders after the cutover date, and returned no blocking validation failures.

## Updated migration path

```text
Shopify API
-> isolated API landing tables
-> API-vs-CSV reconciliation
-> scheduled API landing
-> shadow raw candidates
-> shadow staging comparison
-> hybrid raw candidates
-> canonical raw rebuild dry run
-> production canonical raw replacement MVP
-> future Airflow automation
```

## Next step

```text
41 - Shopify API Canonical Raw Replacement MVP
```

Goal:

```text
Manually replace the production Shopify canonical raw tables using validated hybrid raw candidates, with backup tables, validation gates, rollback steps, and no Airflow automation yet.
```
