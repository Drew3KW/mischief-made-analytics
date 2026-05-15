# 42 - Shopify API Canonical Refresh Automation MVP

## Summary

This milestone automated the Shopify API canonical refresh flow in Airflow.

The project now has one master DAG that can pull fresh Shopify API data, rebuild API raw candidates, rebuild hybrid raw candidates, back up canonical raw, replace canonical raw, refresh the warehouse, and validate the result.

## What changed

Added a master orchestration DAG:

```text
dags/mm_shopify_api_canonical_refresh_mvp.py
```

Added automated backup and rollback SQL:

```text
sql/raw/backup_shopify_canonical_raw_pre_automated_refresh.sql
sql/raw/rollback_shopify_canonical_raw_from_pre_automated_refresh_backups.sql
```

Updated child DAG schedules so they are trigger-only helpers:

```text
dags/mm_shopify_api_orders_landing_mvp.py
dags/mm_shopify_api_customers_landing_mvp.py
dags/mm_shopify_api_products_landing_mvp.py
dags/mm_bigquery_refresh_mvp.py
```

## Automated flow

The new master DAG runs the full refresh sequence:

```text
Shopify API landing
-> API raw candidates
-> API raw candidate validation gate
-> hybrid raw candidates
-> hybrid raw candidate validation gate
-> latest canonical raw backup
-> canonical raw replacement
-> warehouse refresh
-> canonical raw replacement validation gate
```

## Scheduling model

The master DAG owns the schedule:

```text
mm_shopify_api_canonical_refresh_mvp
```

The following DAGs remain available but are now trigger-only helpers:

```text
mm_shopify_api_orders_landing_mvp
mm_shopify_api_customers_landing_mvp
mm_shopify_api_products_landing_mvp
mm_bigquery_refresh_mvp
```

This avoids duplicate independent refreshes and keeps the pipeline sequence controlled by one orchestrator.

## Validation gates

The master DAG blocks on validation checks before continuing.

Validation gates include:

```text
sql/validation/shopify_api_raw_candidates_validation.sql
sql/validation/shopify_hybrid_raw_candidate_validation.sql
sql/validation/shopify_canonical_raw_replacement_validation.sql
```

If any validation query returns `FAIL` rows, the DAG fails at that gate instead of continuing silently.

## Backup and rollback

Before canonical raw replacement, the DAG creates latest backup tables:

```text
raw_load.shopify_products_pre_automated_refresh_backup_latest
raw_load.shopify_customers_pre_automated_refresh_backup_latest
raw_load.shopify_orders_pre_automated_refresh_backup_latest
```

Rollback SQL was added for manual recovery if needed:

```text
sql/raw/rollback_shopify_canonical_raw_from_pre_automated_refresh_backups.sql
```

After rollback, `mm_bigquery_refresh_mvp` should be run so downstream tables reflect the restored canonical raw tables.

## Validation

The new master DAG was triggered manually in the Airflow UI and completed successfully.

Result:

```text
mm_shopify_api_canonical_refresh_mvp: success
```

This confirms that the full automated Shopify API refresh flow can run end-to-end from Airflow.

## Non-goals

This milestone did not:

- Move Airflow to the cloud
- Remove the CSV ingestion fallback
- Add Etsy, Faire, or ads data
- Modify staging model SQL
- Modify marts model SQL
- Modify business-facing analysis SQL
- Build BI dashboards

## Result

Milestone 42 successfully automated the Shopify API-backed canonical refresh flow.

The warehouse can now be updated through a single orchestrated Airflow DAG that lands fresh Shopify API data, rebuilds canonical raw, refreshes downstream models, and validates the result.

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
-> automated canonical refresh MVP
-> operational hardening and runbook
```

## Next step


```text
43 - Automated Shopify Refresh Operations and Runbook
```

Goal:

```text
Harden the automated Shopify refresh workflow with concise operational documentation, freshness checks, failure-handling guidance, and rollback instructions.
```
