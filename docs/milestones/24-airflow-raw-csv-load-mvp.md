# 24 - Airflow Raw CSV Load MVP

## Summary

Extended the local Airflow MVP from warehouse refresh + validation into raw Shopify CSV ingestion.

This milestone adds a new local Airflow DAG:

- `mm_shopify_raw_load_and_refresh_mvp`

The new DAG now supports a full local batch flow across the current Shopify source set:

- `customers`
- `products`
- `orders`

Current end-to-end ingestion DAG flow:

- `check_input_files`
- `raw_load`
- `raw_rebuild`
- `staging`
- `marts`
- `analysis`
- `validation`

The goal of this phase was to automate the full current Shopify CSV source set coherently, rather than automating only part of the raw layer and leaving loose ends between ingestion and the downstream warehouse.

## What changed

### New ingestion DAG

Added:

- `dags/mm_shopify_raw_load_and_refresh_mvp.py`

This DAG introduces a second local orchestration path alongside the existing warehouse refresh DAG.

Current DAG responsibilities:

- checks for required local Shopify CSV files
- loads the latest CSVs into landing tables in `raw_load`
- rebuilds canonical `raw` tables from existing history plus the latest landed data
- runs the existing warehouse refresh flow through:
  - `staging`
  - `marts`
  - `analysis`
  - `validation`

### New raw rebuild SQL layer

Added:

- `sql/raw/rebuild_shopify_customers.sql`
- `sql/raw/rebuild_shopify_products.sql`
- `sql/raw/rebuild_shopify_orders.sql`

These files rebuild the canonical Shopify raw tables after each landing load.

### Local raw-load landing dataset

Introduced a new BigQuery landing dataset:

- `raw_load`

Landing tables currently used:

- `raw_load.shopify_customers_latest`
- `raw_load.shopify_products_latest`
- `raw_load.shopify_orders_latest`

These act as short-lived latest-import landing tables, while canonical history continues to live in:

- `raw.shopify_customers`
- `raw.shopify_products`
- `raw.shopify_orders`

### Local file-drop convention

Added a local ignored CSV drop path for manual Shopify exports:

- `local_data/shopify/`

Expected filenames:

- `customers.csv`
- `products.csv`
- `orders.csv`

`.gitignore` was updated so local source files are not committed to the repo.

## Ingestion design decisions

### Keep the existing refresh DAG, add a second ingest + refresh DAG

Rather than expanding `mm_bigquery_refresh_mvp` into an all-purpose pipeline, this milestone adds a second DAG for source ingestion plus downstream rebuild.

This keeps two clean local workflows available:

- refresh from existing raw tables
- ingest new source files and then rebuild the warehouse

That separation keeps the local MVP easier to understand, test, and explain in a portfolio.

### Land latest files into `raw_load`, then rebuild canonical raw

The project needs to preserve historical source context for BI and downstream warehouse analysis.

Because of that, this milestone does **not** simply replace canonical raw tables with the newest CSV files.

Instead, the pattern is:

1. load the newest CSV file into a landing table
2. combine landing data with existing canonical raw history
3. deduplicate into a rebuilt canonical raw table

This keeps history intact while still using a simple batch-oriented local MVP.

### Keep raw typing simple: all `STRING`

The raw-layer design principle remains unchanged:

- manual schema
- all columns loaded as `STRING`
- typing / parsing / business logic deferred to `staging`

This keeps raw ingestion resilient to messy Shopify exports and source drift.

### Preserve established raw naming contracts

The raw-layer naming contracts established earlier in the project were preserved:

- `shopify_customers` and `shopify_products` use sanitized snake_case column names
- `shopify_orders` preserves original Shopify-style column names

This matters because the existing staging models already depend on those raw schemas.

## Raw rebuild logic

### Customers

`raw.shopify_customers` is rebuilt by combining historical canonical raw with the latest landed customer CSV and deduplicating with the following preference order:

1. `customer_id`
2. normalized `email`
3. lightweight row fingerprint fallback

When the same key appears in both old and new data, the incoming row wins.

### Products

`raw.shopify_products` is rebuilt by combining historical canonical raw with the latest landed product CSV and deduplicating primarily on:

1. normalized `variant_sku`
2. fallback composite key from `handle + option values`
3. fallback `handle + title`

This milestone also required explicit schema alignment between the historical canonical product raw table and the current Shopify export format.

### Orders

`raw.shopify_orders` is rebuilt at approximate line-item business identity, not at order-level only.

This is important because the raw orders export feeds `stg_shopify_order_items` and is effectively line-item-grain, so `Name` alone is not sufficient as a raw dedupe key.

The orders rebuild therefore uses a line-item-oriented fingerprint built from fields such as:

- `Name`
- `Lineitem sku`
- `Lineitem name`
- `Lineitem quantity`
- `Lineitem price`
- `Created at`
- `Email`

## Issues encountered and resolved

### Customers CSV parsing required quoted-newline support

The first ingestion runs showed that the current Shopify customers export can contain embedded newline behavior that breaks default CSV parsing.

This was resolved by enabling quoted-newline handling for:

- `load_raw_customers_csv`

### Products CSV parsing also required quoted-newline support

The same class of parsing issue appeared in the products export.

This was resolved by enabling quoted-newline handling for:

- `load_raw_products_csv`

### Product export schema drift broke raw rebuild

The first draft of `rebuild_shopify_products.sql` used `SELECT *` on both canonical raw and landing tables.

This failed because the current Shopify products export no longer matches the historical canonical raw schema exactly.

The current export introduced:

- renamed metafield-related columns
- additional market / pricing columns

This was resolved by rewriting the rebuild SQL to:

- explicitly select the historical canonical raw columns
- map renamed landing columns back to canonical names
- ignore extra new export-only columns for MVP

### Local Airflow example-DAG residue interfered with CLI behavior

While testing the new DAG, local Airflow CLI behavior was disrupted by stale example DAG metadata and unstable standalone state.

This was resolved by cleaning out stale example-DAG metadata from the local Airflow SQLite metadata DB and then restarting local Airflow cleanly.

### Local Airflow UI became unreliable during repeated iterative testing

During iterative DAG edits and repeated local runs, the web UI became unreliable enough that CLI-based triggering and state inspection became the more dependable debugging path.

The pipeline itself still executed successfully once local Airflow process state was cleaned up.

## Result

The new ingestion DAG now runs successfully end to end:

- `check_input_files`
- `raw_load.load_raw_customers_csv`
- `raw_load.load_raw_products_csv`
- `raw_load.load_raw_orders_csv`
- `raw_rebuild.rebuild_shopify_customers`
- `raw_rebuild.rebuild_shopify_products`
- `raw_rebuild.rebuild_shopify_orders`
- downstream `staging`
- downstream `marts`
- downstream `analysis`
- downstream `validation`

All downstream validation tasks pass after raw ingestion and rebuild.

## Why this matters

This milestone improves the project in two important ways.

### 1. Business / engineering value

The local warehouse is no longer limited to rebuilding from previously loaded raw tables.

It can now ingest the full current Shopify CSV source set and rebuild the warehouse in one local orchestrated flow.

That makes the project more realistic as an actual business-support system.

### 2. Portfolio quality

The repo now demonstrates more than static warehouse modeling and scheduled refreshes.

It now shows a realistic local analytics engineering pattern involving:

- source file ingestion
- landing tables
- canonical raw rebuilds
- schema drift handling
- downstream warehouse refresh
- validation gating

## Next likely steps

With local raw CSV ingestion now working, the next major directions could include one or more of:

- documentation / operational polish for the ingestion DAG
- better local observability and logging
- broader source ingestion expansion
- BI/dashboarding
- future multi-source integration:
  - Etsy
  - Faire
  - Etsy Ads
  - Pinterest Ads
- later migration toward dbt + Snowflake
