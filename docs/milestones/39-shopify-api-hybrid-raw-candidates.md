# 39 - Shopify API Hybrid Raw Candidate Tables

## Summary

This milestone created non-production hybrid raw candidate tables in `raw_load`.

The goal was to prototype the future canonical raw rebuild pattern by combining current CSV-derived raw history with API-derived raw candidate data, without replacing production canonical raw tables.

## What changed

Added hybrid raw candidate build SQL:

```text
sql/raw/create_shopify_products_hybrid_raw_candidate.sql
sql/raw/create_shopify_customers_hybrid_raw_candidate.sql
sql/raw/create_shopify_orders_hybrid_raw_candidate.sql
```

Added validation SQL:

```text
sql/validation/shopify_hybrid_raw_candidate_validation.sql
```

Created hybrid raw candidate tables:

```text
raw_load.shopify_products_hybrid_raw_candidate
raw_load.shopify_customers_hybrid_raw_candidate
raw_load.shopify_orders_hybrid_raw_candidate
```

## Design

The hybrid candidates remain isolated in `raw_load`.

Products and customers use a deduped hybrid pattern:

```text
current CSV-derived raw
+
API-derived raw candidate
->
hybrid raw candidate
```

For overlapping product and customer records, API-derived candidate rows are preferred.

Orders use a cutover-date pattern:

```text
CSV-derived raw order history before cutover date
+
API-derived raw order rows on or after cutover date
->
hybrid raw order candidate
```

The derived API cutover date was:

```text
2026-04-23
```

This preserves historical CSV-derived order data while allowing API-derived forward order data to enter the hybrid candidate.

## Non-goals

This milestone did not:

- Replace `raw.shopify_products`
- Replace `raw.shopify_customers`
- Replace `raw.shopify_orders`
- Modify production staging models
- Modify marts models
- Modify business-facing analysis models
- Add DAG behavior
- Remove the CSV fallback path

## Validation

The validation query completed successfully.

No checks returned:

```text
FAIL
```

All validation checks returned either:

```text
PASS
INFO
```

Key passing checks included:

```text
product_hybrid_current_staging_skus_missing: 0
customer_hybrid_duplicate_customer_ids: 0
customer_hybrid_current_staging_ids_missing: 0
order_hybrid_duplicate_line_item_fingerprints: 0
order_hybrid_missing_order_numbers: 0
order_hybrid_created_at_parse_failures: 0
order_hybrid_quantity_cast_failures: 0
order_hybrid_price_cast_failures: 0
order_hybrid_csv_rows_on_or_after_cutover: 0
order_hybrid_api_rows_before_cutover: 0
order_hybrid_current_staging_orders_missing_before_cutover: 0
order_hybrid_line_item_count_differences_before_cutover: 0
```

Important informational results included:

```text
product_hybrid_rows: 2963
product_hybrid_api_source_rows: 2430
customer_hybrid_rows: 21468
customer_hybrid_missing_email_rows: 817
customer_hybrid_api_source_rows: 21467
order_hybrid_rows: 48573
order_hybrid_api_cutover_date: 2026-04-23
order_hybrid_api_forward_rows: 96
order_hybrid_current_raw_history_rows_preserved: 48477
order_hybrid_orders_missing_from_current_staging: 46
```

## Result

Milestone 39 successfully prototyped the future hybrid canonical raw rebuild pattern.

The hybrid order candidate preserved CSV-derived order history before the cutover date and added API-derived forward order rows on or after the cutover date.

The validation results show that the hybrid raw candidate layer is structurally sound and ready for a dry-run milestone.

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
-> eventual production canonical raw replacement
```

## Next step

Recommended next milestone:

```text
40 - Shopify API Canonical Raw Rebuild Dry Run
```

Suggested goal:

```text
Use the hybrid raw candidates to run a safe dry run of the canonical raw rebuild path and compare resulting staging outputs before any production raw replacement is considered.
```
