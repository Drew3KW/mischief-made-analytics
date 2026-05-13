# 41 - Shopify API Canonical Raw Replacement MVP

## Summary

This milestone completed the first manual production canonical raw replacement using validated Shopify API-backed hybrid raw candidates.

The replacement moved the Shopify API path from shadow/candidate/dry-run work into production canonical raw while preserving the CSV historical baseline, keeping the CSV fallback available, and leaving Airflow automation for a future milestone.

## What changed

Added manual backup, replacement, rollback, and validation SQL:

```text
sql/raw/backup_shopify_canonical_raw_pre_api_replacement.sql
sql/raw/replace_shopify_canonical_raw_from_hybrid_candidates.sql
sql/raw/rollback_shopify_canonical_raw_from_pre_api_replacement_backups.sql
sql/validation/shopify_canonical_raw_replacement_validation.sql
```

Updated existing order candidate SQL to preserve the full legacy Shopify CSV raw orders schema:

```text
sql/raw/create_shopify_orders_api_raw_candidate.sql
sql/raw/create_shopify_orders_hybrid_raw_candidate.sql
```

## Production tables replaced

The following canonical raw tables were manually replaced from validated hybrid raw candidates:

```text
raw.shopify_products
raw.shopify_customers
raw.shopify_orders
```

The source hybrid candidate tables were:

```text
raw_load.shopify_products_hybrid_raw_candidate
raw_load.shopify_customers_hybrid_raw_candidate
raw_load.shopify_orders_hybrid_raw_candidate
```

## Run sequence

The milestone was executed manually in this order:

```text
1. Trigger Shopify API landing DAGs:
   mm_shopify_api_orders_landing_mvp
   mm_shopify_api_customers_landing_mvp
   mm_shopify_api_products_landing_mvp

2. Rebuild API raw candidates.

3. Rebuild hybrid raw candidates.

4. Back up current canonical raw tables.

5. Replace canonical raw tables from hybrid raw candidates.

6. Run mm_bigquery_refresh_mvp.

7. Run canonical raw replacement validation.
```

## Schema preservation fix

Initial validation caught that `raw.shopify_orders` was missing legacy CSV export columns after replacement.

The orders API raw candidate and hybrid raw candidate were updated so API-forward order rows preserve the full legacy raw orders schema, with unavailable API fields populated as `NULL`.

After rerunning the replacement and warehouse refresh, the schema validation passed.

## Validation

The final replacement validation passed successfully.

No checks returned:

```text
FAIL
```

Key passing validation areas included:

```text
raw schema compatibility
product raw row count match
customer raw row count match
order raw row count match
candidate SKU preservation
candidate customer ID preservation
candidate order line item fingerprint preservation
API-forward order item inclusion
production staging rebuild success
```

Production staging tables rebuilt successfully after replacement:

```text
staging.stg_shopify_products
staging.stg_shopify_customers
staging.stg_shopify_order_items
staging.stg_shopify_orders
```

## Non-goals

This milestone did not:

- Automate canonical raw replacement in Airflow
- Remove the CSV fallback path
- Modify staging model SQL
- Modify marts model SQL
- Modify business-facing analysis SQL
- Add dashboard changes
- Add cloud scheduling

## Result

Milestone 41 successfully replaced production Shopify canonical raw tables with validated API-backed hybrid raw tables.

The warehouse now contains preserved CSV historical data plus API-forward Shopify data in production canonical raw, and downstream staging, marts, analysis, and validation refresh successfully from that new canonical raw foundation.

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
42 - Shopify API Canonical Raw Automation Planning and MVP
```

Goal:

```text
Design and implement a safe Airflow-controlled version of the canonical raw rebuild flow, with validation gates and rollback awareness, while keeping the local CSV ingestion fallback available.
```
