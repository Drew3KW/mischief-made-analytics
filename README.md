# Mischief Made Analytics

Analytics engineering portfolio project for Mischief Made, an apparel brand.

This project is both:

1. A real business decision-support system for Mischief Made
2. A flagship portfolio project for an analytics engineering / data engineering career pivot

The project models Shopify and Etsy sales data in BigQuery. Shopify ingestion has evolved from local CSV exports to an API-backed canonical refresh path orchestrated by Airflow. Etsy ingestion now includes historical receipt and transaction coverage across the trusted Shopify modeling window.

## Goals

- Build a reliable analytics warehouse for Mischief Made
- Support analysis of revenue, products, customers, and trends
- Add multi-channel ecommerce visibility across Shopify and Etsy
- Practice production-style analytics engineering workflows
- Demonstrate SQL, BigQuery, Python, Airflow, Docker, Git, API ingestion, validation, and data modeling skills
- Create a foundation for future BI, dbt, and Snowflake work

## Stack

- BigQuery
- Shopify CSV exports
- Shopify Admin API
- Etsy Open API
- SQL
- Python
- Apache Airflow 3
- Docker Compose
- WSL / Ubuntu
- VS Code
- GitHub

## Repository structure

```text
dags/             Airflow DAGs
docs/milestones/ Milestone writeups
docs/operations/ Operational runbooks
docs/spikes/     Exploratory technical notes
scripts/         Local helper and extraction scripts
sql/analysis/    Business-facing analysis SQL
sql/marts/       Fact, dimension, semantic, and reusable mart models
sql/raw/         Canonical raw rebuild, replacement, backup, and rollback SQL
sql/staging/     Cleaned and typed source models
sql/validation/  QA, reconciliation, and validation SQL
```

## BigQuery layers

```text
raw       canonical raw source tables
raw_load  file/API landing, shadow, candidate, backup, and dry-run tables
staging   cleaned and typed source models
marts     dimensional models, fact tables, and analysis views
```

## Source systems

Current source coverage:

- Shopify orders CSV export
- Shopify products CSV export
- Shopify customers CSV export
- Shopify Admin API product, variant, customer, order, and line item data
- Etsy Open API receipts
- Etsy Open API receipt transactions
- partial Etsy Open API receipt payments

Exploratory Etsy coverage:

- Etsy Open API ledger entries

Future sources:

- Faire
- Etsy Ads
- Pinterest Ads

## Core Shopify models

Staging:

```text
stg_shopify_order_items
stg_shopify_orders
stg_shopify_products
stg_shopify_customers
```

Marts:

```text
dim_products
dim_products_historical
product_family_map
dim_product_families
dim_customers
fct_order_items
fct_orders
```

## Cross-channel revenue models

The first validated cross-channel revenue layer combines mature Shopify order facts with Etsy receipt and payment landing data.

Cross-channel mart:

```text
marts.fct_cross_channel_orders
```

Daily analysis views:

```text
marts.anl_cross_channel_revenue_daily
marts.anl_cross_channel_revenue_daily_pivot
```

Validation:

```text
sql/validation/cross_channel_revenue_validation.sql
```

The cross-channel order model uses channel-aware order keys:

```text
shopify:<order_number>
etsy:<receipt_id>
```

The model supports:

- Shopify plus Etsy daily revenue
- channel-level order counts
- all-channel daily revenue totals
- side-by-side Shopify/Etsy daily comparison
- refund-aware net revenue
- partial Etsy fee visibility
- Etsy payment-enrichment edge-case flags

The model does not yet perform:

- cross-channel customer identity resolution
- Etsy product/listing catalog modeling
- Shopify/Etsy product-family harmonization
- full Etsy payout or accounting reconciliation

## Orchestration

The project uses Docker Compose as the preferred local Airflow runtime.

Primary automated Shopify refresh DAG:

```text
mm_shopify_api_canonical_refresh_mvp
```

Primary Etsy historical backfill DAG:

```text
mm_etsy_historical_backfill_mvp
```

The Shopify master DAG orchestrates API landing, validation, canonical raw replacement, warehouse refresh, and replacement validation.

The Etsy historical backfill DAG uses a BigQuery state table to process historical receipt/transaction chunks until the backfill is complete or Etsy returns a rate limit.

Operational Shopify guidance:

```text
docs/operations/shopify_api_canonical_refresh_runbook.md
```

## Etsy status

Completed Etsy work:

- Etsy Open API app approval
- API key and shared secret connectivity test
- OAuth authorization flow
- authenticated shop/user lookup
- receipt sample retrieval
- receipt transaction sample retrieval
- receipt payment sample retrieval
- ledger entry sample retrieval
- field inventory generation
- recent Etsy landing MVP
- historical Etsy receipt/transaction backfill automation
- promotion of historical backfill candidates to latest landing tables

Etsy landing script:

```text
scripts/etsy_orders_landing.py
```

Etsy state table:

```text
raw_load.etsy_historical_backfill_chunks
```

Current Etsy landing tables:

```text
raw_load.etsy_receipts_api_latest
raw_load.etsy_receipt_transactions_api_latest
raw_load.etsy_receipt_payments_api_latest
```

Current Etsy historical coverage:

```text
receipts:     16,496 rows, 2021-01-31 to 2026-05-20
transactions: 23,422 rows, 2021-01-31 to 2026-05-20
payments:        273 rows, 2021-01-31 to 2021-03-01
```

Payment history is partial and will be enriched separately.

## Local development

Start Airflow:

```bash
docker compose up airflow-init
docker compose up -d
```

Open Airflow:

```text
http://localhost:8080
```

Check services:

```bash
docker compose ps
```

Check DAG discovery:

```bash
docker compose exec airflow-apiserver airflow dags list
```

Check DAG import errors:

```bash
docker compose exec airflow-apiserver airflow dags list-import-errors
```

Stop Airflow:

```bash
docker compose down
```

Run Etsy orders landing locally:

```bash
python scripts/etsy_orders_landing.py --days 30
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
local_data/etsy_api_spike/
logs/
```

The committed `.env.example` documents expected local environment variables.

## Modeling principles

- Trusted dates are the default for business-facing analysis.
- `order_number` is the practical business-facing order key for Shopify.
- `customer_email` is the practical customer key for Shopify.
- Etsy order identity starts from `receipt_id`.
- Etsy order-item identity starts from `transaction_id`.
- Cross-channel models use channel-aware keys.
- Shared semantic logic lives upstream in reusable marts models.
- Summary-layer models are BI-friendly and built on validated upstream logic.
- Raw ingestion and canonical raw rebuild are separate concerns.
- New source systems begin in isolated landing or spike layers before joining production models.
- Cross-channel customer and revenue logic must be explicit, validated, and channel-aware.

## Current status

Completed:

- Analysis Pack v1
- Dashboard-ready Shopify summary layers
- Dockerized local Airflow orchestration
- Local Shopify CSV ingestion
- Shopify Admin API extraction spike
- Shopify Bulk Operation proof of concept
- Isolated Shopify API landing for products, customers, and orders
- Shopify API-vs-CSV reconciliation
- Shopify API hybrid raw candidates
- Shopify API production canonical raw replacement MVP
- Shopify API automated canonical refresh MVP
- Automated Shopify refresh operations and runbook
- Etsy source integration spike
- Etsy orders landing MVP
- Cross-channel revenue model MVP
- Etsy historical receipts and transactions backfill

Next focus:

- Etsy historical payments enrichment

## Roadmap

- Etsy historical payments enrichment
- Business Dashboard MVP
- Etsy staging and marts
- Cross-channel customer modeling
- Cross-channel product and product-family harmonization
- Cloud-hosted scheduled ingestion and refresh
- Faire integration
- Etsy Ads integration
- Pinterest Ads integration
- Eventual migration to dbt + Snowflake

## About

BigQuery-based analytics engineering project for Mischief Made, building a real warehouse and business analysis layer from Shopify, Etsy, and future multi-channel ecommerce data to support decision-making, portfolio development, BI, dbt, and Snowflake migration.
