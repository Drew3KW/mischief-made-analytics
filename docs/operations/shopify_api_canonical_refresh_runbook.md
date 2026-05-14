# Shopify API Canonical Refresh Runbook

## Purpose

This runbook explains how to operate the automated Shopify API canonical refresh flow.

The automated refresh is controlled by:

```text
mm_shopify_api_canonical_refresh_mvp
```

This DAG updates the warehouse from fresh Shopify API data through a validated canonical raw replacement and downstream warehouse refresh.

## Normal flow

The master DAG runs this sequence:

```text
Shopify API landing
-> API landing freshness validation
-> API raw candidates
-> API raw candidate validation
-> hybrid raw candidates
-> hybrid raw candidate validation
-> latest canonical raw backup
-> canonical raw replacement
-> warehouse refresh
-> canonical raw replacement validation
```

## Scheduling model

The master DAG owns the schedule:

```text
mm_shopify_api_canonical_refresh_mvp
```

The following DAGs are trigger-only helpers:

```text
mm_shopify_api_orders_landing_mvp
mm_shopify_api_customers_landing_mvp
mm_shopify_api_products_landing_mvp
mm_bigquery_refresh_mvp
```

They should remain available in Airflow, but they should not own independent schedules for the normal automated Shopify refresh flow.

## How to run manually

In the Airflow UI:

```text
1. Open http://localhost:8080
2. Open mm_shopify_api_canonical_refresh_mvp
3. Click Trigger DAG
4. Watch the graph view until the run succeeds or fails
```

Expected result:

```text
success
```

## How to confirm fresh landing data

Run:

```sql
SELECT
  'orders' AS landing_table,
  COUNT(*) AS row_count,
  MAX(api_extracted_at) AS latest_api_extracted_at
FROM `mischief-made-analytics.raw_load.shopify_orders_api_latest`

UNION ALL

SELECT
  'order_line_items',
  COUNT(*),
  MAX(api_extracted_at)
FROM `mischief-made-analytics.raw_load.shopify_order_line_items_api_latest`

UNION ALL

SELECT
  'customers',
  COUNT(*),
  MAX(api_extracted_at)
FROM `mischief-made-analytics.raw_load.shopify_customers_api_latest`

UNION ALL

SELECT
  'products',
  COUNT(*),
  MAX(api_extracted_at)
FROM `mischief-made-analytics.raw_load.shopify_products_api_latest`

UNION ALL

SELECT
  'product_variants',
  COUNT(*),
  MAX(api_extracted_at)
FROM `mischief-made-analytics.raw_load.shopify_product_variants_api_latest`;
```

Expected result:

```text
row_count > 0 for every table
latest_api_extracted_at is recent
```

## Validation gates

The automated refresh blocks on these validation files:

```text
sql/validation/shopify_api_landing_freshness_validation.sql
sql/validation/shopify_api_raw_candidates_validation.sql
sql/validation/shopify_hybrid_raw_candidate_validation.sql
sql/validation/shopify_canonical_raw_replacement_validation.sql
```

Expected result for each validation gate:

```text
FAIL: 0
```

If any validation returns `FAIL` rows, the master DAG should stop at that gate.

## Backup tables

Before replacing canonical raw, the master DAG writes latest backup tables:

```text
raw_load.shopify_products_pre_automated_refresh_backup_latest
raw_load.shopify_customers_pre_automated_refresh_backup_latest
raw_load.shopify_orders_pre_automated_refresh_backup_latest
```

These backups represent the immediately previous canonical raw state before the latest automated replacement attempt.

They are not historical archives.

## Rollback

If a refresh needs to be rolled back, run:

```text
sql/raw/rollback_shopify_canonical_raw_from_pre_automated_refresh_backups.sql
```

Then run:

```text
mm_bigquery_refresh_mvp
```

This restores canonical raw from the latest automated refresh backups and refreshes downstream staging, marts, analysis, and validation tables from the restored raw data.

## Failure handling

### API landing failure

If one of the child API landing DAGs fails:

```text
1. Open the failed child DAG run in Airflow.
2. Inspect the failed task logs.
3. Fix the source issue.
4. Rerun mm_shopify_api_canonical_refresh_mvp.
```

No canonical raw replacement should occur if API landing fails.

### API landing freshness failure

If `validate_api_landing_freshness_no_failures` fails:

```text
1. Check whether API landing tables have row counts greater than zero.
2. Check MAX(api_extracted_at) in the landing tables.
3. Rerun the master DAG after confirming the API landing DAGs can write fresh data.
```

No canonical raw replacement should occur if freshness validation fails.

### API raw candidate validation failure

If `validate_api_raw_candidates_no_failures` fails:

```text
1. Run sql/validation/shopify_api_raw_candidates_validation.sql manually.
2. Review the FAIL rows.
3. Fix the candidate build issue.
4. Rerun the master DAG.
```

No canonical raw replacement should occur if this validation fails.

### Hybrid raw candidate validation failure

If `validate_hybrid_raw_candidates_no_failures` fails:

```text
1. Run sql/validation/shopify_hybrid_raw_candidate_validation.sql manually.
2. Review the FAIL rows.
3. Fix the hybrid candidate issue.
4. Rerun the master DAG.
```

No canonical raw replacement should occur if this validation fails.

### Canonical raw replacement validation failure

If `validate_canonical_raw_replacement_no_failures` fails:

```text
1. Run sql/validation/shopify_canonical_raw_replacement_validation.sql manually.
2. Review the FAIL rows.
3. If needed, run rollback SQL.
4. Run mm_bigquery_refresh_mvp after rollback.
```

This is the only validation gate that runs after canonical raw replacement.

## Safe manual recovery sequence

Use this only if canonical raw needs to be restored from the latest automated refresh backup:

```text
1. Run sql/raw/rollback_shopify_canonical_raw_from_pre_automated_refresh_backups.sql
2. Trigger mm_bigquery_refresh_mvp
3. Run sql/validation/shopify_canonical_raw_replacement_validation.sql
4. Confirm FAIL: 0
```

## Current limitations

This is still a local Airflow workflow.

The process depends on:

```text
local machine awake
Docker running
Airflow services healthy
local credentials available
```

Future cloud scheduling should move this flow to a hosted environment.