# Mischief Made Analytics

BigQuery-based analytics engineering project for Mischief Made, an apparel brand.

This project is designed to be both:

1. a real business decision-support system
2. a flagship portfolio project for an analytics engineering / data engineering career pivot

## Goals

This project serves two purposes:

1. Help Mischief Made make better business decisions
2. Demonstrate real-world analytics engineering skills in a portfolio project

## Current stack

- BigQuery
- Shopify CSV exports
- Shopify Admin API
- SQL
- Apache Airflow 3
- Docker Compose
- WSL / Ubuntu local development
- VS Code
- GitHub

## Current warehouse structure

- `raw`: canonical raw source history
- `raw_load`: source-file and API landing tables used before canonical raw rebuild decisions
- `staging`: cleaned and typed source models
- `marts`: dimensional models and fact tables
- `sql/analysis`: business-facing analysis queries and semantic analysis-layer models
- `sql/validation`: QA and validation queries
- `docs/milestones`: milestone writeups documenting major project steps
- `docs/spikes`: exploratory technical notes and comparison writeups
- `dags/`: Airflow orchestration DAGs
- `scripts/`: local helper scripts

## Current source systems

- Shopify orders CSV export
- Shopify products CSV export
- Shopify customers CSV export
- Shopify Admin API spike outputs
- Shopify Admin API product and variant landing tables

## Core models

### Staging

- `stg_shopify_order_items`
- `stg_shopify_orders`
- `stg_shopify_products`
- `stg_shopify_customers`

### Marts

- `dim_products`
- `dim_products_historical`
- `product_family_map`
- `dim_product_families`
- `dim_customers`
- `fct_order_items`
- `fct_orders`

## Current analysis layer

### Family-level performance and trends

- `anl_product_performance_by_family`
- `anl_product_revenue_monthly_by_family`
- `anl_product_family_recent_trends`

### Customer-level analysis

- `anl_customer_order_behavior`
- `anl_customer_recency_segments`
- `anl_customer_cohort_retention`
- `anl_customer_rfm_segments`

### Dashboard-ready summary layers

- `anl_daily_kpi_summary`
- `anl_monthly_business_summary`
- `anl_customer_summary`
- `anl_family_summary`

### Customer x product-family analysis

- `anl_product_family_customer_mix`

### Supporting validation

Validation SQL lives under:

```text
sql/validation/
```

Machine-readable Airflow assertions live under:

```text
sql/validation/assertions/
```

These assertions act as pass / fail data quality gates at the end of orchestrated warehouse refreshes.

## Current orchestration layer

The project uses Docker Compose as the preferred local Airflow runtime.

Current Docker Compose services:

- `postgres`
- `airflow-apiserver`
- `airflow-scheduler`
- `airflow-dag-processor`
- `airflow-init`

Current DAGs:

- `mm_bigquery_refresh_mvp`
  - refreshes staging, marts, analysis, and validation from existing raw tables
- `mm_shopify_raw_load_and_refresh_mvp`
  - loads local Shopify CSV files, rebuilds canonical raw tables, refreshes the warehouse, and runs validation
- `mm_shopify_api_extract_spike`
  - extracts small Shopify Admin GraphQL API samples to local JSON files
- `mm_shopify_bulk_operation_spike`
  - runs a Shopify Bulk Operation products/variants export to local JSONL
- `mm_shopify_api_products_landing_mvp`
  - runs a Shopify products/variants Bulk Operation and loads isolated API landing tables in BigQuery

The CSV ingestion DAG remains the known-good ingestion path.

The API landing DAG writes only to isolated `raw_load` tables and does not modify canonical raw tables or downstream business logic.

## Local Docker Airflow workflow

The preferred local workflow is:

1. edit files in VS Code
2. run Docker Compose commands from the VS Code terminal
3. use the Airflow localhost web UI for DAG triggering and task inspection

### Prerequisites

- Docker Desktop for Windows
- WSL integration enabled in Docker Desktop
- VS Code with WSL workflow
- GCP service account key available locally
- Shopify CSV exports available locally
- Shopify app credentials available locally for API DAGs

### Local-only files

The following files and folders are required or generated locally and should not be committed:

```text
.env
keys/gcp-sa.json
local_data/shopify/*.csv
local_data/shopify_api_spike/
local_data/shopify_bulk_spike/
local_data/shopify_api_landing/
logs/
```

### Environment setup

Copy the committed environment template:

```bash
cp .env.example .env
```

Then edit `.env` locally as needed.

Important local environment values include:

- `GOOGLE_APPLICATION_CREDENTIALS`
- `AIRFLOW_CONN_GOOGLE_CLOUD_DEFAULT`
- `AIRFLOW__API_AUTH__JWT_SECRET`
- local Airflow admin username/password values
- `SHOPIFY_SHOP_DOMAIN`
- `SHOPIFY_ADMIN_API_VERSION`
- `SHOPIFY_API_CLIENT_ID`
- `SHOPIFY_API_CLIENT_SECRET`

The `.env` file is intentionally ignored by Git.

### Expected local files

Place the GCP service account key here:

```text
keys/gcp-sa.json
```

Place Shopify CSV exports here:

```text
local_data/shopify/customers.csv
local_data/shopify/products.csv
local_data/shopify/orders.csv
```

### Start Airflow

From the repo root:

```bash
docker compose up airflow-init
docker compose up -d
```

Then open:

```text
http://localhost:8080
```

Local login defaults are controlled by `.env`.

### Check Airflow services

```bash
docker compose ps
```

Expected services:

- `postgres`
- `airflow-apiserver`
- `airflow-scheduler`
- `airflow-dag-processor`
- `airflow-init`

### Check DAG discovery

```bash
docker compose exec airflow-apiserver airflow dags list
```

Expected DAGs:

- `mm_bigquery_refresh_mvp`
- `mm_shopify_raw_load_and_refresh_mvp`
- `mm_shopify_api_extract_spike`
- `mm_shopify_bulk_operation_spike`
- `mm_shopify_api_products_landing_mvp`

### Stop Airflow

```bash
docker compose down
```

If services were renamed or stale containers remain:

```bash
docker compose down --remove-orphans
```

## Shopify API workflow

The project includes Shopify Admin API extraction and landing work.

### Small GraphQL sample extraction DAG

```text
mm_shopify_api_extract_spike
```

Local output:

```text
local_data/shopify_api_spike/
```

Field inventory helper:

```bash
python scripts/inspect_shopify_api_samples.py
```

Generated local output:

```text
local_data/shopify_api_spike/field_inventory.md
```

### Bulk Operation proof-of-concept DAG

```text
mm_shopify_bulk_operation_spike
```

Local output:

```text
local_data/shopify_bulk_spike/
```

Expected local files include:

```text
products_bulk_start_response.json
products_bulk_completed_status.json
products_bulk_result.jsonl
products_bulk_result_summary.md
```

These outputs are local scratch data and should not be committed.

### Products API landing MVP DAG

```text
mm_shopify_api_products_landing_mvp
```

Local output:

```text
local_data/shopify_api_landing/
```

BigQuery landing tables:

```text
raw_load.shopify_products_api_latest
raw_load.shopify_product_variants_api_latest
```

Validation query:

```text
sql/validation/shopify_api_products_landing_validation.sql
```

Current validated API landing counts:

```text
Product: 671
ProductVariant: 2436
```

The API landing path is isolated. It does not replace the CSV ingestion path, rebuild canonical raw tables, or change downstream staging, marts, or analysis logic.

Current migration plan:

```text
Shopify API -> isolated API landing tables -> API-vs-CSV comparison layer -> eventual canonical raw rebuild
```

## Key modeling lessons so far

- Shopify raw exports are messy and best ingested as strings first
- Order grain and line-item grain must be validated carefully
- `order_number` is the most practical business-facing order key
- `customer_email` is the current practical customer key
- Current product exports do not fully represent historical sold products
- Historical product coverage required a dedicated product spine
- Shared semantic logic should live upstream in reusable marts models rather than being repeated downstream
- Raw ingestion and canonical raw rebuild are separate concerns
- Local environment variables should be documented with `.env.example`, while real local values live in uncommitted `.env`
- Local secrets, data drops, API outputs, and runtime logs should stay out of Git and Docker image build context
- Direct Shopify API ingestion should be developed in parallel with the current CSV ingestion path until API-derived outputs are reconciled
- Bulk Operation JSONL output is useful for larger Shopify exports, but needs normalization before warehouse loading
- API landing tables should remain isolated until reconciliation proves they can safely support canonical raw rebuild changes

## Major project milestones so far

### Analysis Pack v1

Analysis Pack v1 established the core warehouse and business-facing analysis foundation, including:

- warehouse foundation
- historical product coverage
- shared product-family models
- upstream core-family filtering
- product-family performance and trends
- customer order behavior
- customer recency segmentation
- customer cohort retention
- product-family x customer behavior analysis
- customer RFM segmentation
- dashboard-ready daily KPI summary
- dashboard-ready monthly business summary
- dashboard-ready monthly customer summary
- dashboard-ready monthly family summary

### Airflow local MVP orchestration

The project moved from standalone SQL development into orchestration with a local Airflow DAG that refreshes the warehouse in dependency order across:

```text
staging -> marts -> analysis
```

This created the foundation for validation, scheduling, raw load automation, and multi-source pipeline growth.

### Airflow validation and scheduled refresh

The orchestration layer was extended with:

- machine-readable validation assertions
- pass / fail data quality gates
- daily scheduled refresh
- lightweight retry settings
- local development safeguards such as `catchup=False` and `max_active_runs=1`

### Airflow raw CSV load MVP

The project added local raw Shopify CSV ingestion through:

```text
mm_shopify_raw_load_and_refresh_mvp
```

This DAG:

- checks local Shopify CSV files
- loads latest CSVs into `raw_load`
- rebuilds canonical `raw` tables
- refreshes staging, marts, analysis, and validation

### Airflow Docker Compose MVP

The local Airflow runtime was migrated from `airflow standalone` to Docker Compose.

This added:

- Postgres metadata database
- Airflow API server / UI
- scheduler
- DAG processor
- initialization service
- custom Airflow image
- mounted repo folders
- mounted local GCP service account key
- environment-backed BigQuery connection

### Docker local environment hardening

The Dockerized local Airflow environment was hardened with:

- `.env.example`
- local-only `.env` workflow
- `.dockerignore`
- improved `.gitignore`
- environment-variable driven Docker Compose configuration

This preserved the working local CSV ingestion path while making the Docker environment more reproducible.

### Shopify API ingestion spike

The project explored direct Shopify Admin API ingestion as a future supplement or replacement for manual Shopify CSV exports.

This milestone added:

- Shopify API local environment configuration
- `mm_shopify_api_extract_spike`
- `scripts/inspect_shopify_api_samples.py`
- `docs/spikes/27-shopify-api-vs-csv-field-comparison.md`
- `mm_shopify_bulk_operation_spike`

The spike proved that Dockerized Airflow can authenticate to Shopify, run GraphQL Admin API queries, write local JSON samples, generate field inventories, and run a Bulk Operation that exports product and product variant data as local JSONL.

The Bulk Operation proof produced:

```text
Product: 671
ProductVariant: 2436
Total JSONL lines: 3107
```

The spike confirmed that Shopify API ingestion is viable, but should continue in parallel with the current CSV pipeline until API-derived outputs are reconciled against the existing warehouse.

### Shopify API landing MVP

The project added the first Shopify API-derived BigQuery landing path.

This milestone added:

- `mm_shopify_api_products_landing_mvp`
- `raw_load.shopify_products_api_latest`
- `raw_load.shopify_product_variants_api_latest`
- `sql/validation/shopify_api_products_landing_validation.sql`

The landing DAG runs a Shopify products/variants Bulk Operation, downloads local JSONL output, separates product and variant records, writes isolated BigQuery landing tables, and validates the parent-child relationship between products and variants.

Validated landing counts:

```text
Product: 671
ProductVariant: 2436
```

This is the first API-derived BigQuery ingestion path in the project. It intentionally does not modify canonical raw tables or downstream business-facing warehouse logic.

## Current focus

Current work is centered on strengthening the project’s ingestion foundation.

The project now has:

- completed Analysis Pack v1
- dashboard-ready summary layers
- Dockerized local Airflow orchestration
- local Shopify CSV ingestion
- machine-readable validation tasks
- Shopify Admin API extraction spike
- Shopify Bulk Operation proof of concept
- isolated Shopify API products/variants landing tables in BigQuery

The next likely milestone is API-vs-CSV product reconciliation, starting with products and variants, while preserving the CSV pipeline as the known-good fallback.

## Future roadmap

- API-vs-CSV product reconciliation layer
- scheduled Shopify API ingestion MVP
- possible canonical raw rebuild from reconciled API data
- BI dashboarding
- additional source integration:
  - Etsy
  - Faire
  - Etsy Ads
  - Pinterest Ads
- cross-channel revenue and marketing analysis
- eventual migration to dbt + Snowflake
