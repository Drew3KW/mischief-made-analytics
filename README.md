# Mischief Made Analytics

Analytics engineering portfolio project for Mischief Made, an apparel brand.

This project is both:

1. a real business decision-support system for Mischief Made
2. a flagship portfolio project for an analytics engineering / data engineering career pivot

The project currently focuses on Shopify sales, product, and customer data, with a roadmap toward multi-source business analytics across Shopify, Etsy, Faire, ads, and BI dashboards.

## Goals

- Build a reliable analytics warehouse for Mischief Made
- Support business analysis around products, customers, revenue, and trends
- Practice production-style analytics engineering workflows
- Demonstrate SQL, BigQuery, Airflow, Docker, Git, and data modeling skills
- Create a foundation for future dbt + Snowflake migration

## Current stack

- BigQuery
- Shopify CSV exports
- Shopify Admin API
- SQL
- Apache Airflow 3
- Docker Compose
- WSL / Ubuntu
- VS Code
- GitHub

## Warehouse structure

- `raw`: canonical raw source tables
- `raw_load`: temporary source-file and API landing tables
- `staging`: cleaned and typed source models
- `marts`: dimensional models, fact tables, and selected analysis views
- `sql/analysis`: business-facing analysis SQL
- `sql/validation`: QA and validation SQL
- `dags`: Airflow DAGs
- `docs/milestones`: milestone writeups
- `docs/spikes`: exploratory technical notes
- `scripts`: local helper scripts

## Source systems

Current:

- Shopify orders CSV export
- Shopify products CSV export
- Shopify customers CSV export
- Shopify Admin API product and variant landing data

Planned:

- Etsy
- Faire
- Etsy Ads
- Pinterest Ads
- additional BI/dashboard outputs

## Core warehouse models

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

### Business-facing analysis

- `anl_product_performance_by_family`
- `anl_product_revenue_monthly_by_family`
- `anl_product_family_recent_trends`
- `anl_customer_order_behavior`
- `anl_customer_recency_segments`
- `anl_customer_cohort_retention`
- `anl_customer_rfm_segments`
- `anl_product_family_customer_mix`
- `anl_daily_kpi_summary`
- `anl_monthly_business_summary`
- `anl_customer_summary`
- `anl_family_summary`
- `anl_shopify_api_csv_product_reconciliation`

## Current orchestration

The project uses Docker Compose as the preferred local Airflow runtime.

Current services:

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

The CSV ingestion DAG remains the known-good fallback path.

The Shopify API path is currently isolated in `raw_load` and is being reconciled before any canonical raw rebuild changes.

## Shopify API progress

The project now includes a working Shopify Admin API product/variant landing path.

API landing tables:

```text
raw_load.shopify_products_api_latest
raw_load.shopify_product_variants_api_latest
```

API landing validation:

```text
sql/validation/shopify_api_products_landing_validation.sql
```

API-vs-CSV reconciliation view:

```text
marts.anl_shopify_api_csv_product_reconciliation
```

Reconciliation SQL:

```text
sql/analysis/shopify_api_csv_product_reconciliation.sql
sql/validation/shopify_api_csv_product_reconciliation_validation.sql
```

Key reconciliation findings:

```text
API variants loaded:                         2,436
Matched API -> CSV raw -> staging -> dim:    2,209
API-only nonblank SKU variants:              0
Duplicate API variant IDs:                   0
Missing SKU variants:                        227
Price differences:                           7
```

The 227 API variants missing SKUs were reviewed and found to be concentrated in non-core products such as socks, pins, wristlets, gift cards, mystery boxes, and accessories.

Current migration path:

```text
Shopify API -> isolated API landing tables -> API-vs-CSV comparison layer -> eventual canonical raw rebuild
```

## Local development workflow

The preferred local workflow is:

1. edit files in VS Code
2. run Docker Compose commands from the VS Code terminal
3. use the Airflow localhost web UI for DAG triggering and task inspection
4. validate results in BigQuery
5. commit code, docs, and validation SQL through Git/GitHub

### Start Airflow

From the repo root:

```bash
docker compose up airflow-init
docker compose up -d
```

Open the Airflow UI:

```text
http://localhost:8080
```

### Check services

```bash
docker compose ps
```

### Check DAG discovery

```bash
docker compose exec airflow-apiserver airflow dags list
```

### Stop Airflow

```bash
docker compose down
```

If stale containers remain:

```bash
docker compose down --remove-orphans
```

## Local-only files

These files and folders are required or generated locally and should not be committed:

```text
.env
keys/gcp-sa.json
local_data/shopify/*.csv
local_data/shopify_api_spike/
local_data/shopify_bulk_spike/
local_data/shopify_api_landing/
logs/
```

The committed `.env.example` documents expected local environment variables.

Important local values include:

- `GOOGLE_APPLICATION_CREDENTIALS`
- `AIRFLOW_CONN_GOOGLE_CLOUD_DEFAULT`
- `AIRFLOW__API_AUTH__JWT_SECRET`
- `SHOPIFY_SHOP_DOMAIN`
- `SHOPIFY_ADMIN_API_VERSION`
- `SHOPIFY_API_CLIENT_ID`
- `SHOPIFY_API_CLIENT_SECRET`

## Modeling principles

- Trusted dates are the default for business-facing analysis
- `order_number` is the practical business-facing order key
- `customer_email` is the practical customer key
- Shared semantic logic should live upstream in reusable marts models
- `fct_order_items` remains at order-item grain
- Summary-layer models should be BI-friendly and built on validated upstream logic
- Raw ingestion and canonical raw rebuild are separate concerns
- API ingestion should remain parallel to CSV ingestion until reconciliation is complete

## Project status

Completed:

- Analysis Pack v1
- dashboard-ready summary layers
- Dockerized local Airflow orchestration
- local Shopify CSV ingestion
- machine-readable validation tasks
- Shopify Admin API extraction spike
- Shopify Bulk Operation proof of concept
- isolated Shopify API product/variant landing tables
- API-vs-CSV product reconciliation

Current focus:

- planning a safe future product rebuild path from API-derived landing data
- preserving the CSV pipeline as the known-good fallback
- continuing toward more automated, multi-source ingestion

## Future roadmap

- API-derived product rebuild planning
- scheduled Shopify API ingestion MVP
- possible canonical raw rebuild from reconciled API data
- BI/dashboarding
- Etsy integration
- Faire integration
- Etsy Ads integration
- Pinterest Ads integration
- cross-channel revenue and marketing analysis
- eventual migration to dbt + Snowflake
