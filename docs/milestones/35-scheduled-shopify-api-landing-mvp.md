# 35 - Scheduled Shopify API Landing MVP

## Summary

This milestone scheduled the isolated Shopify Admin API landing DAGs for products, customers, and orders.

The goal was to move API landing from manual-only runs to scheduled local Airflow runs while preserving the existing CSV ingestion pipeline as the known-good fallback.

The milestone succeeded.

## What changed

Updated schedules for the three API landing DAGs:

```text
dags/mm_shopify_api_orders_landing_mvp.py
dags/mm_shopify_api_customers_landing_mvp.py
dags/mm_shopify_api_products_landing_mvp.py
```

Scheduled local run times:

```text
Orders API landing:     20:00 UTC, roughly 1:00 PM Pacific during daylight time
Customers API landing:  20:30 UTC, roughly 1:30 PM Pacific during daylight time
Products API landing:   21:00 UTC, roughly 2:00 PM Pacific during daylight time
```

The schedules are staggered to keep Shopify Bulk Operations, Airflow logs, and local debugging easier to reason about.

Each DAG remains configured with:

```text
catchup=False
max_active_runs=1
```

This prevents local Airflow from trying to backfill missed runs and prevents overlapping runs of the same DAG.

## Validation

Confirmed in Dockerized Airflow:

- no DAG import errors
- API landing DAGs visible in Airflow
- schedules display correctly in the Airflow UI

Updated DAGs:

```text
mm_shopify_api_orders_landing_mvp
mm_shopify_api_customers_landing_mvp
mm_shopify_api_products_landing_mvp
```

## Design decisions

This milestone schedules API landing only.

It intentionally does not:

- replace Shopify CSV ingestion
- modify canonical `raw.shopify_*` tables
- modify staging models
- modify marts models
- modify business-facing analysis models
- trigger downstream warehouse refreshes from API landing data
- remove the CSV fallback path

The schedules are optimized for local development because Airflow currently runs on a local machine. Scheduled runs are expected only when:

```text
Docker Desktop is running
Docker Compose Airflow services are up
the computer is awake
```

Overnight / early-morning BI-ready refreshes are a better fit for a future cloud-hosted scheduler, not the current local machine.

Current migration path:

```text
Shopify API -> isolated API landing tables -> API-vs-CSV reconciliation -> scheduled API landing -> eventual canonical raw rebuild
```

## Result

The project now has scheduled local API landing coverage for:

- products
- product variants
- customers
- orders
- order line items

This is the first scheduled Shopify API ingestion layer in the project.

## Next step

Next milestone:

```text
36 - Shopify API Canonical Raw Rebuild Planning
```

Goal:

```text
Design a safe future path from reconciled API landing tables toward canonical raw rebuild logic, without replacing the current CSV-derived warehouse yet.
```
