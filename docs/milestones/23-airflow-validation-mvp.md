# 23 - Airflow Validation MVP

## Summary

Extended the local Airflow MVP from warehouse refresh orchestration into machine-readable validation.

This milestone adds a first validation task group to the existing `mm_bigquery_refresh_mvp` DAG so the pipeline now runs:

- `staging`
- `marts`
- `analysis`
- `validation`

The goal of this phase was to introduce pass / fail validation gates before moving further into refresh scheduling or raw CSV load orchestration.

## What changed

### New SQL assertion layer

Added machine-readable validation SQL files under:

- `sql/validation/assertions/dim_customers_assertions.sql`
- `sql/validation/assertions/fct_orders_assertions.sql`
- `sql/validation/assertions/fct_order_items_assertions.sql`
- `sql/validation/assertions/product_family_models_assertions.sql`
- `sql/validation/assertions/anl_daily_kpi_summary_assertions.sql`

These complement the existing human-review-oriented validation layer in `sql/validation/` by providing Airflow-friendly pass / fail checks using BigQuery `ASSERT`.

### Airflow DAG update

Updated:

- `dags/mm_bigquery_refresh_mvp.py`

The DAG now includes a `validation` task group downstream of the warehouse refresh flow.

Current DAG flow:

- `staging -> marts -> analysis -> validation`

Validation tasks added:

- `validate_dim_customers`
- `validate_fct_orders`
- `validate_fct_order_items`
- `validate_product_family_models`
- `validate_anl_daily_kpi_summary`

### Local Airflow configuration cleanup

Local Airflow setup was also tightened so the repo DAG folder is used consistently by default and example DAG noise is removed from local testing.

## Validation design decisions

### Keep machine assertions separate from review queries

The project already had a strong `sql/validation/` layer, but many of those files were designed for analyst review rather than direct Airflow gating.

This milestone intentionally adds a second layer of narrower assertion files rather than rewriting all existing validation SQL at once.

That keeps:

- review queries available for investigation and business QA
- assertion files focused on DAG pass / fail behavior

### Validate model contracts, not assumptions

During implementation, the first assertion drafts surfaced an important semantic issue:

- `dim_customers` is not a complete universe of all non-null `customer_email` values that appear in order facts
- some valid fact rows may contain customer emails not present in the Shopify customers export-derived dimension

As a result, customer coverage assertions were removed from:

- `fct_orders_assertions.sql`
- `fct_order_items_assertions.sql`

Validation was revised to reflect actual model contracts rather than an overly strict dimensional assumption.

### Reuse real model logic inside assertions

The daily KPI summary assertions were aligned to the actual model logic and warehouse schema rather than a simplified placeholder version.

This included:

- referencing the correct target dataset / table
- reusing the warehouse’s real cancellation logic via:
  - `cancelled_at_ts`
  - `financial_status`
- avoiding references to nonexistent fields such as `order_status`

## Validation coverage in MVP

### `dim_customers`

Checks include:

- no duplicate `customer_email`
- no null / blank `customer_email`
- no missing nonblank customer-export emails from `stg_shopify_customers`

### `fct_orders`

Checks include:

- row-count tieout to `stg_shopify_orders`
- no duplicate `order_number`

### `fct_order_items`

Checks include:

- row-count tieout to `stg_shopify_order_items`
- no duplicate `order_item_key`
- no missing `product_key` coverage relative to `dim_products_historical`

### Shared product-family layer

Checks include:

- no duplicate `product_key` in `product_family_map`
- no duplicate `product_family_key` in `dim_product_families`
- expected family-map coverage alignment

### Daily KPI summary

Checks include:

- no null `order_date`
- one row per `order_date`
- completed order tieout
- gross revenue tieout

## Issues encountered and resolved

### Airflow DAG folder persistence

At first, local task testing repeatedly failed because Airflow was still pointing at the default `~/airflow/dags` path in new shell sessions.

This was resolved by updating local Airflow config so the repo `dags/` directory is used by default.

### Missing assertion file blocked DAG parsing

The first validation DAG revision referenced `anl_daily_kpi_summary_assertions.sql` before the file had actually been created locally.

Because the DAG reads SQL file contents at import time, the missing file prevented DAG loading. Creating the file resolved this.

### Assertion / model contract mismatch

Initial customer coverage assertions failed because they assumed complete fact-to-dimension customer coverage that the warehouse does not actually guarantee.

These assertions were revised or removed so the validation layer now tests the intended contract of each model.

### Dataset and schema alignment

The daily KPI assertion file initially referenced the wrong dataset and a nonexistent order-status field.

Those references were updated to match the actual warehouse objects and logic.

## Result

All five validation tasks now pass in Airflow:

- `validate_dim_customers`
- `validate_fct_orders`
- `validate_fct_order_items`
- `validate_product_family_models`
- `validate_anl_daily_kpi_summary`

The project now has a working local Airflow validation layer that can serve as the final task group in the warehouse refresh DAG.

## Why this matters

This milestone moves the project from:

- local SQL modeling with review queries

to:

- orchestrated warehouse refresh with explicit machine-readable validation gates

That improves the project in two ways:

1. business / engineering trust:
   - model refreshes can now fail fast when key data contracts break

2. portfolio quality:
   - the repo now demonstrates not just warehouse modeling, but also orchestration and data quality enforcement in a realistic analytics engineering workflow

## Next likely steps

With local orchestration and validation now both working, the next major phase can reasonably move toward one or both of:

- refresh scheduling
- raw CSV load orchestration
