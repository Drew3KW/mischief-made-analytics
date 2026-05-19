# Mischief Made Analytics

Analytics engineering portfolio project for Mischief Made, an apparel brand.

This project is both:

1. A real business decision-support system for Mischief Made
2. A flagship portfolio project for an analytics engineering / data engineering career pivot

The project currently uses Shopify and Etsy data to model ecommerce sales, products, customers, and business trends. Shopify ingestion has evolved from local CSV exports to an API-backed canonical refresh path orchestrated by Airflow. Etsy ingestion now has an isolated BigQuery landing MVP for receipts, receipt transactions, and receipt payments.

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

## Warehouse structure

- `raw`: canonical raw source tables
- `raw_load`: temporary source-file, API landing, API shadow, hybrid candidate, backup, and dry-run tables
- `staging`: cleaned and typed source models
- `marts`: dimensional models, fact tables, and selected analysis views
- `sql/analysis`: business-facing analysis SQL
- `sql/validation`: QA and validation SQL
- `dags`: Airflow DAGs
- `docs/milestones`: milestone writeups
- `docs/operations`: operational runbooks
- `docs/spikes`: exploratory technical notes
- `scripts`: local helper scripts

## Source systems

Current production source coverage:

- Shopify orders CSV export
- Shopify products CSV export
- Shopify customers CSV export
- Shopify Admin API product, variant, customer, order, and line item data

Current landing source coverage:

- Etsy Open API receipts
- Etsy Open API receipt transactions
- Etsy Open API receipt payments

Exploratory source coverage:

- Etsy Open API ledger entries

Planned:

- Cross-channel Shopify plus Etsy revenue model
- Faire
- Etsy Ads
- Pinterest Ads
- BI/dashboard outputs

## Core Shopify models

Staging:

- `stg_shopify_order_items`
- `stg_shopify_orders`
- `stg_shopify_products`
- `stg_shopify_customers`

Marts:

- `dim_products`
- `dim_products_historical`
- `product_family_map`
- `dim_product_families`
- `dim_customers`
- `fct_order_items`
- `fct_orders`

Business-facing analysis includes product-family performance, customer behavior, cohort retention, RFM segmentation, daily KPIs, monthly summaries, and API-vs-CSV reconciliation outputs.

## Orchestration

The project uses Docker Compose as the preferred local Airflow runtime.

The primary automated Shopify refresh DAG is:

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

The CSV ingestion DAG remains the known-good fallback path.

Operational guidance is documented in:

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

Current API landing tables:

```text
raw_load.shopify_products_api_latest
raw_load.shopify_product_variants_api_latest
raw_load.shopify_customers_api_latest
raw_load.shopify_orders_api_latest
raw_load.shopify_order_line_items_api_latest
```

Current API raw candidate tables:

```text
raw_load.shopify_products_api_raw_candidate
raw_load.shopify_customers_api_raw_candidate
raw_load.shopify_orders_api_raw_candidate
```

Current hybrid raw candidate tables:

```text
raw_load.shopify_products_hybrid_raw_candidate
raw_load.shopify_customers_hybrid_raw_candidate
raw_load.shopify_orders_hybrid_raw_candidate
```

Current canonical raw tables use the validated API-backed hybrid pattern:

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

Current API validation coverage:

- Product and variant API landing validation
- Product API-vs-CSV reconciliation
- Customer API landing validation
- Customer API-vs-CSV reconciliation
- Order API landing validation
- Order API-vs-CSV reconciliation
- API shadow raw candidate validation
- API shadow staging comparison
- Hybrid raw candidate validation
- Canonical raw rebuild dry-run validation
- Canonical raw replacement validation
- API landing freshness validation
- Automated canonical refresh validation gates

Current Shopify migration path:

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

## Etsy API status

Etsy source integration has advanced from spike to landing MVP.

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

Validated row summary:

```text
receipts=173, transactions=254, payments=169
```

Validation completed with:

```text
PASS: 19
REVIEW: 2
INFO: 2
FAIL: 0
```

Known Etsy landing edge cases:

- 4 receipts did not return payment records from the receipt-payment endpoint.
- 1 receipt transaction had a blank SKU.
- These edge cases are tracked as `REVIEW` items and do not block landing.

Etsy is not yet wired into production warehouse refreshes or cross-channel models.

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
- Cross-channel models must use channel-aware keys.
- Shared semantic logic should live upstream in reusable marts models.
- `fct_order_items` remains at order-item grain.
- Summary-layer models should be BI-friendly and built on validated upstream logic.
- Raw ingestion and canonical raw rebuild are separate concerns.
- API landing, raw candidate shaping, canonical raw replacement, and warehouse refresh are separate steps.
- CSV ingestion remains available as a fallback path.
- Automated canonical raw refresh should include freshness checks, validation gates, rollback awareness, and operational documentation.
- New source systems should begin in isolated landing or spike layers before joining production models.
- Cross-channel customer and revenue logic should be explicit, validated, and channel-aware.

## Current status

Completed:

- Analysis Pack v1
- Dashboard-ready summary layers
- Dockerized local Airflow orchestration
- Local Shopify CSV ingestion
- Machine-readable validation tasks
- Shopify Admin API extraction spike
- Shopify Bulk Operation proof of concept
- Isolated Shopify API landing for products, customers, and orders
- API-vs-CSV reconciliation for products, customers, and orders
- Scheduled local Shopify API landing
- Shopify API canonical raw rebuild planning
- Shopify API shadow raw candidate tables
- Shopify API shadow staging comparison
- Shopify API hybrid raw candidate tables
- Shopify API canonical raw rebuild dry run
- Shopify API production canonical raw replacement MVP
- Shopify API automated canonical refresh MVP
- Automated Shopify refresh operations and runbook
- Etsy source integration spike
- Etsy orders landing MVP

Next focus:

- Cross-channel Shopify plus Etsy revenue modeling
- BI/dashboarding after cross-channel revenue coverage

## Roadmap

- Cross-channel revenue model MVP
- Business dashboard MVP
- Etsy Airflow orchestration
- Cloud-hosted scheduled ingestion and refresh
- Faire integration
- Etsy Ads integration
- Pinterest Ads integration
- Cross-channel marketing analysis
- Eventual migration to dbt + Snowflake

## About

BigQuery-based analytics engineering project for Mischief Made, building a real warehouse and business analysis layer from Shopify, Etsy, and future multi-channel ecommerce data to support decision-making, portfolio development, BI, dbt, and Snowflake migration.
