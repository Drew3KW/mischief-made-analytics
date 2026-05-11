# Mischief Made Analytics

Analytics engineering portfolio project for Mischief Made, an apparel brand.

This project is both:

1. A real business decision-support system for Mischief Made
2. A flagship portfolio project for an analytics engineering / data engineering career pivot

The project currently uses Shopify data to model sales, products, customers, and business trends, with a roadmap toward multi-source analytics across Shopify, Etsy, Faire, ads, and BI dashboards.

## Goals

- Build a reliable analytics warehouse for Mischief Made
- Support analysis of revenue, products, customers, and trends
- Practice production-style analytics engineering workflows
- Demonstrate SQL, BigQuery, Airflow, Docker, Git, and data modeling skills
- Create a foundation for future dbt + Snowflake migration

## Stack

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
- `raw_load`: temporary source-file, API landing, API shadow, and hybrid candidate tables
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
- Shopify Admin API product, variant, customer, order, and line item landing data

Planned:

- Etsy
- Faire
- Etsy Ads
- Pinterest Ads
- BI/dashboard outputs

## Core models

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

Current DAGs:

- `mm_bigquery_refresh_mvp`
- `mm_shopify_raw_load_and_refresh_mvp`
- `mm_shopify_api_extract_spike`
- `mm_shopify_bulk_operation_spike`
- `mm_shopify_api_products_landing_mvp`
- `mm_shopify_api_customers_landing_mvp`
- `mm_shopify_api_orders_landing_mvp`

The CSV ingestion DAG remains the known-good fallback path.

The Shopify API path currently lands data into isolated `raw_load` tables and is being validated before any production canonical raw rebuild changes.

## Shopify API status

Working scheduled local API landing coverage:

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

Current API shadow raw candidate tables:

```text
raw_load.shopify_products_api_raw_candidate
raw_load.shopify_customers_api_raw_candidate
raw_load.shopify_orders_api_raw_candidate
```

Current API shadow staging tables:

```text
raw_load.stg_shopify_products_api_shadow
raw_load.stg_shopify_customers_api_shadow
raw_load.stg_shopify_order_items_api_shadow
raw_load.stg_shopify_orders_api_shadow
```

Current API hybrid raw candidate tables:

```text
raw_load.shopify_products_hybrid_raw_candidate
raw_load.shopify_customers_hybrid_raw_candidate
raw_load.shopify_orders_hybrid_raw_candidate
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
- API hybrid raw candidate validation

Current migration path:

```text
Shopify API
-> isolated API landing tables
-> API-vs-CSV reconciliation
-> scheduled API landing
-> shadow raw candidates
-> shadow staging comparison
-> hybrid raw candidates
-> canonical raw rebuild dry run
-> eventual production canonical raw replacement
```

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

Stop Airflow:

```bash
docker compose down
```

Remove stale containers if needed:

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

## Modeling principles

- Trusted dates are the default for business-facing analysis
- `order_number` is the practical business-facing order key
- `customer_email` is the practical customer key
- Shared semantic logic should live upstream in reusable marts models
- `fct_order_items` remains at order-item grain
- Summary-layer models should be BI-friendly and built on validated upstream logic
- Raw ingestion and canonical raw rebuild are separate concerns
- API ingestion should remain parallel to CSV ingestion until validation is complete
- API-derived shadow and hybrid layers should be validated before touching production canonical raw

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

Next focus:

- Canonical raw rebuild dry run
- Future production canonical raw rebuild from reconciled API data
- Future cloud-hosted scheduling for reliable overnight refreshes
- BI/dashboarding

## Roadmap

- Possible production canonical raw rebuild from reconciled API data
- Cloud-hosted scheduled ingestion and refresh
- BI/dashboarding
- Etsy integration
- Faire integration
- Etsy Ads integration
- Pinterest Ads integration
- Cross-channel revenue and marketing analysis
- Eventual migration to dbt + Snowflake
