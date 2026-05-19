# Mischief Made Analytics

Analytics engineering portfolio project for Mischief Made, an apparel brand.

This project is both:

1. A real business decision-support system for Mischief Made
2. A flagship portfolio project for an analytics engineering / data engineering career pivot

The project currently models Shopify and Etsy sales data in BigQuery. Shopify ingestion has evolved from local CSV exports to an API-backed canonical refresh path orchestrated by Airflow. Etsy ingestion has progressed from API spike to validated landing tables. The warehouse now includes the first validated cross-channel Shopify plus Etsy revenue model.

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

Current production source coverage:

- Shopify orders CSV export
- Shopify products CSV export
- Shopify customers CSV export
- Shopify Admin API product, variant, customer, order, and line item data

Current Etsy source coverage:

- Etsy Open API receipts
- Etsy Open API receipt transactions
- Etsy Open API receipt payments

Exploratory Etsy coverage:

- Etsy Open API ledger entries

Planned future sources:

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

Business-facing analysis includes product-family performance, customer behavior, cohort retention, RFM segmentation, daily KPIs, monthly summaries, and API-vs-CSV reconciliation outputs.

## Cross-channel revenue models

The first validated cross-channel revenue layer combines mature Shopify order facts with Etsy receipt/payment landing data.

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
- Etsy fee visibility
- Etsy edge-case flags

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

This master DAG orchestrates:

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

Trigger-only helper DAGs:

```text
mm_shopify_api_orders_landing_mvp
mm_shopify_api_customers_landing_mvp
mm_shopify_api_products_landing_mvp
mm_bigquery_refresh_mvp
```

Additional DAGs:

```text
mm_shopify_raw_load_and_refresh_mvp
mm_shopify_api_extract_spike
mm_shopify_bulk_operation_spike
```

The CSV ingestion DAG remains the known-good Shopify fallback path.

Operational guidance:

```text
docs/operations/shopify_api_canonical_refresh_runbook.md
```

Etsy landing currently runs through a local Python script and is not yet wired into Airflow.

## Shopify API status

Working Shopify API coverage:

- Products
- Product variants
- Customers
- Orders
- Order line items

Current Shopify API landing tables:

```text
raw_load.shopify_products_api_latest
raw_load.shopify_product_variants_api_latest
raw_load.shopify_customers_api_latest
raw_load.shopify_orders_api_latest
raw_load.shopify_order_line_items_api_latest
```

Current canonical raw Shopify tables use the validated API-backed hybrid pattern:

```text
raw.shopify_products
raw.shopify_customers
raw.shopify_orders
```

For orders, canonical raw preserves CSV-derived history before the API cutover date and includes API-forward rows on or after the cutover date.

The legacy Shopify CSV raw orders schema is preserved, with API-unavailable legacy fields populated as `NULL` for API-forward rows.

Current automated backup tables:

```text
raw_load.shopify_products_pre_automated_refresh_backup_latest
raw_load.shopify_customers_pre_automated_refresh_backup_latest
raw_load.shopify_orders_pre_automated_refresh_backup_latest
```

Current Shopify validation coverage includes:

- API landing validation
- API-vs-CSV reconciliation
- API shadow raw candidate validation
- API shadow staging comparison
- Hybrid raw candidate validation
- Canonical raw dry-run validation
- Canonical raw replacement validation
- API landing freshness validation
- Automated refresh validation gates

## Etsy API status

Completed Etsy spike coverage:

- Etsy Open API app approval
- API key and shared secret connectivity test
- OAuth authorization flow
- authenticated shop/user lookup
- receipt sample retrieval
- receipt transaction sample retrieval
- receipt payment sample retrieval
- ledger entry sample retrieval
- field inventory generation

Spike documentation:

```text
docs/spikes/etsy-source-integration-spike.md
```

Local spike helper:

```text
scripts/etsy_api_probe.py
```

Completed Etsy landing coverage:

- receipt/order-header landing
- receipt transaction/order-item landing
- receipt payment landing
- landing-level validation

Landing script:

```text
scripts/etsy_orders_landing.py
```

Current Etsy landing tables:

```text
raw_load.etsy_receipts_api_latest
raw_load.etsy_receipt_transactions_api_latest
raw_load.etsy_receipt_payments_api_latest
```

Landing validation:

```text
sql/validation/etsy_orders_landing_validation.sql
```

Validated landing result:

```text
receipts=173
transactions=254
payments=169
FAIL=0
```

Known Etsy landing edge cases:

- 4 receipts did not return payment records from the receipt-payment endpoint.
- 1 receipt transaction had a blank SKU.
- These edge cases are tracked as review items at landing and carried forward where relevant.

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

Remove stale containers if needed:

```bash
docker compose down --remove-orphans
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
- `fct_order_items` remains at order-item grain.
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
- API-vs-CSV reconciliation for products, customers, and orders
- Scheduled local Shopify API landing
- Shopify API shadow raw candidates and staging comparison
- Shopify API hybrid raw candidates
- Shopify API canonical raw rebuild dry run
- Shopify API production canonical raw replacement MVP
- Shopify API automated canonical refresh MVP
- Automated Shopify refresh operations and runbook
- Etsy source integration spike
- Etsy orders landing MVP
- Cross-channel revenue model MVP

Next focus:

- Etsy Historical Backfill MVP

## Roadmap

- Etsy historical backfill
- Business Dashboard MVP
- Etsy Airflow orchestration
- Etsy staging and marts
- Cross-channel customer modeling
- Cross-channel product and product-family harmonization
- Cloud-hosted scheduled ingestion and refresh
- Faire integration
- Etsy Ads integration
- Pinterest Ads integration
- Cross-channel marketing analysis
- Eventual migration to dbt + Snowflake

## About

BigQuery-based analytics engineering project for Mischief Made, building a real warehouse and business analysis layer from Shopify, Etsy, and future multi-channel ecommerce data to support decision-making, portfolio development, BI, dbt, and Snowflake migration.
