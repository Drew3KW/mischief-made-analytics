# Mischief Made Analytics

Analytics engineering portfolio project for Mischief Made, an apparel brand.

This project is both:

1. A real business decision-support system for Mischief Made
2. A flagship portfolio project for an analytics engineering / data engineering career pivot

The project uses BigQuery, SQL, Airflow, Docker, Shopify data, and Etsy data to model sales, products, customers, revenue trends, and cross-channel business performance.

## Goals

- Build a reliable analytics warehouse for Mischief Made
- Support analysis of revenue, products, customers, and trends
- Practice production-style analytics engineering workflows
- Demonstrate SQL, BigQuery, Airflow, Docker, Git, API ingestion, and data modeling skills
- Create a foundation for future BI dashboards, dbt, and Snowflake migration

## Stack

- BigQuery
- Shopify CSV exports
- Shopify Admin API
- Etsy Open API
- SQL
- Apache Airflow 3
- Docker Compose
- WSL / Ubuntu
- VS Code
- GitHub

## Warehouse structure

- `raw`: canonical raw source tables
- `raw_load`: source-file loads, API landing tables, candidates, backups, state tables, and operational validation data
- `staging`: cleaned and typed source models
- `marts`: dimensional models, fact tables, and selected reusable business models
- `sql/analysis`: business-facing analysis SQL
- `sql/validation`: QA and validation SQL
- `dags`: Airflow DAGs
- `docs/milestones`: milestone writeups
- `docs/spikes`: exploratory technical notes
- `docs/operations`: operational runbooks
- `scripts`: local helper and API ingestion scripts

## Source systems

Current:

- Shopify orders CSV export
- Shopify products CSV export
- Shopify customers CSV export
- Shopify Admin API product, variant, customer, order, and line item data
- Etsy Open API receipts, receipt transactions, and receipt payments

Planned:

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
- `fct_cross_channel_orders`

Business-facing analysis includes product-family performance, customer behavior, cohort retention, RFM segmentation, daily KPIs, monthly summaries, API-vs-CSV reconciliation outputs, and cross-channel Shopify/Etsy revenue analysis.

## Cross-channel revenue outputs

Current cross-channel outputs:

```text
marts.fct_cross_channel_orders
analysis.cross_channel_revenue_daily
analysis.cross_channel_revenue_daily_pivot
```

The cross-channel revenue model combines:

- Shopify order facts from mature Shopify marts
- Etsy receipt/payment landing data from Etsy API latest tables

Cross-channel order keys are channel-aware:

```text
shopify:<order_number>
etsy:<receipt_id>
```

This avoids key collisions while preserving the practical source-system order identifiers.

## Orchestration

The project uses Docker Compose as the preferred local Airflow runtime.

### Primary Shopify refresh DAG

```text
mm_shopify_api_canonical_refresh_mvp
```

This master DAG orchestrates:

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

Trigger-only Shopify helper DAGs:

```text
mm_shopify_api_orders_landing_mvp
mm_shopify_api_customers_landing_mvp
mm_shopify_api_products_landing_mvp
mm_bigquery_refresh_mvp
```

Additional Shopify DAGs:

```text
mm_shopify_raw_load_and_refresh_mvp
mm_shopify_api_extract_spike
mm_shopify_bulk_operation_spike
```

The CSV ingestion DAG remains the known-good Shopify fallback path.

### Primary Etsy recent refresh DAG

```text
mm_etsy_recent_refresh_mvp
```

This DAG keeps the current Etsy landing and cross-channel revenue layer fresh.

Flow:

```text
Etsy recent API landing
-> recent candidate promotion to latest
-> Etsy landing validation gate
-> fct_cross_channel_orders
-> cross_channel_revenue_daily
-> cross_channel_revenue_daily_pivot
-> cross-channel validation gate
```

### Etsy historical backfill DAGs

Completed historical backfill DAGs:

```text
mm_etsy_historical_backfill_mvp
mm_etsy_historical_payments_backfill_mvp
```

These DAGs were used to backfill Etsy receipts, receipt transactions, and receipt payments. They are paused after completion.

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
- Automated canonical refresh validation gates

## Etsy API status

Working Etsy API coverage:

- Authenticated shop/user lookup
- Receipts
- Receipt transactions
- Receipt payments
- Ledger entries explored during source spike

Current Etsy latest landing tables:

```text
raw_load.etsy_receipts_api_latest
raw_load.etsy_receipt_transactions_api_latest
raw_load.etsy_receipt_payments_api_latest
```

Historical Etsy receipt and transaction coverage has been backfilled to match the trusted Shopify modeling window beginning `2021-01-31`.

Historical Etsy payment enrichment has also been completed. Receipt-level 404 responses from the Etsy payment endpoint are recorded as expected skipped receipts rather than treated as pipeline failures.

Current Etsy validation coverage:

- landing row counts
- required key checks
- duplicate receipt/payment/transaction key checks
- receipt/transaction parent-child checks
- payment coverage checks
- blank SKU review checks
- cross-channel revenue validation

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

Restart Airflow services after adding or changing DAGs:

```bash
docker compose restart airflow-dag-processor airflow-scheduler airflow-apiserver
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
local_data/etsy_api_spike/
logs/
```

The committed `.env.example` documents expected local environment variables.

## Modeling principles

- Trusted dates are the default for business-facing analysis
- `order_number` is the practical Shopify business-facing order key
- `customer_email` is the practical Shopify customer key
- Etsy order identity starts from `receipt_id`
- Etsy order-item identity starts from `transaction_id`
- Cross-channel models use channel-aware keys
- Shared semantic logic should live upstream in reusable marts models
- `fct_order_items` remains at order-item grain
- Summary-layer models should be BI-friendly and built on validated upstream logic
- Raw ingestion and canonical raw rebuild are separate concerns
- API landing, candidate shaping, canonical promotion, and warehouse refresh are separate steps
- CSV ingestion remains available as a Shopify fallback path
- Automated refresh paths should include validation gates and rollback awareness

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
- Shopify API operational hardening and runbook
- Etsy source integration spike
- Etsy orders landing MVP
- Cross-channel revenue model MVP
- Etsy historical receipts and transactions backfill
- Etsy historical payments enrichment
- Etsy recent refresh orchestration

Next focus:

- Business Dashboard MVP
- Etsy staging and marts
- Cross-channel customer/product hardening

## Roadmap

- Business dashboard MVP
- Etsy staging and marts
- Cross-channel customer/product hardening
- Cloud-hosted scheduled ingestion and refresh
- Faire integration
- Etsy Ads integration
- Pinterest Ads integration
- Cross-channel marketing analysis
- Eventual migration to dbt + Snowflake
