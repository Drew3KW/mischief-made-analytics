# 37 - Shopify API Shadow Raw Candidate Tables

## Summary

This milestone created API-derived shadow raw candidate tables in `raw_load`.

These tables reshape isolated Shopify API landing data into CSV-compatible raw-style table contracts for validation. They do not replace canonical raw tables and do not affect staging, marts, analysis, or DAG behavior.

## What changed

Added raw candidate build SQL:

```text
sql/raw/create_shopify_products_api_raw_candidate.sql
sql/raw/create_shopify_customers_api_raw_candidate.sql
sql/raw/create_shopify_orders_api_raw_candidate.sql
```

Added validation SQL:

```text
sql/validation/shopify_api_raw_candidates_validation.sql
```

Created shadow candidate tables:

```text
raw_load.shopify_products_api_raw_candidate
raw_load.shopify_customers_api_raw_candidate
raw_load.shopify_orders_api_raw_candidate
```

## Design

The candidate tables adapt Shopify API landing data into the existing CSV-derived raw table shape.

Current API landing path:

```text
Shopify API
-> raw_load.shopify_*_api_latest
```

New shadow candidate path:

```text
Shopify API
-> raw_load.shopify_*_api_latest
-> raw_load.shopify_*_api_raw_candidate
```

The purpose is to test whether API-derived data can satisfy the existing raw/staging contracts before any future canonical raw replacement.

## Non-goals

This milestone did not:

- Replace `raw.shopify_products`
- Replace `raw.shopify_customers`
- Replace `raw.shopify_orders`
- Modify staging models
- Modify marts models
- Modify business-facing analysis models
- Add DAG behavior
- Remove the CSV fallback path

## Validation

The validation query completed successfully.

All checks returned either:

```text
PASS
INFO
```

No validation checks returned `FAIL`.

The validation covered:

- Candidate table row counts
- Candidate row count alignment with API landing tables
- Product SKU coverage and blank SKU review
- Customer ID duplication checks
- Customer email coverage review
- Order line-item grain alignment
- Order number completeness
- Timestamp parse compatibility
- Quantity and price cast compatibility
- Overlap with current staging data

## Result

The project now has a safe shadow layer for testing API-derived raw contracts.

This moves the migration path forward while keeping the current CSV-derived warehouse intact.

Updated migration path:

```text
Shopify API
-> isolated API landing tables
-> API-vs-CSV reconciliation
-> scheduled API landing
-> shadow raw candidates
-> eventual canonical raw rebuild
```

## Next step

Next milestone:

```text
38 - Shopify API Shadow Staging Comparison
```

Goal:

```text
Compare API-derived raw candidates against current staging outputs before deciding whether to update canonical raw rebuild logic.
```
