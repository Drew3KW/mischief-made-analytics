# Mischief Made Analytics

Mischief Made Analytics is a BigQuery and Airflow analytics engineering project for Mischief Made, an apparel business selling through Shopify, Etsy, and other channels.

The project serves two purposes:

1. Build a real business decision-support system for Mischief Made.
2. Serve as a flagship analytics engineering / data engineering portfolio project.

The current system ingests Shopify and Etsy data, models trusted business metrics in BigQuery, validates core outputs, orchestrates refreshes with Airflow, and powers a private Looker Studio business dashboard MVP.

## Current Stack

- BigQuery
- SQL
- Shopify CSV exports
- Shopify Admin API
- Etsy Open API
- Apache Airflow 3
- Docker Compose
- WSL / Ubuntu local development
- VS Code
- GitHub
- Looker Studio

## Current Status

The project currently supports:

- Shopify CSV fallback ingestion
- Shopify API landing and canonical raw refresh
- Etsy API historical landing/backfill
- Etsy payment enrichment
- Etsy recent refresh orchestration
- Shopify staging, marts, and analysis models
- Etsy staging, marts, and dimension models
- Cross-channel Shopify/Etsy revenue modeling
- Dashboard-facing BigQuery views
- Private Looker Studio Business Dashboard MVP
- Validation queries for key marts, analysis outputs, Etsy models, cross-channel revenue, and dashboard outputs

## Repository Structure

- `dags/`
  - Airflow DAGs for local orchestration

- `scripts/`
  - Python scripts for API extraction, landing, and backfill workflows

- `sql/raw/`
  - Raw rebuild, promotion, candidate, and rollback SQL

- `sql/staging/`
  - Staging models

- `sql/marts/`
  - Core facts, dimensions, and shared semantic models

- `sql/analysis/`
  - Business-facing analysis and dashboard views

- `sql/validation/`
  - Validation queries and assertion-style checks

- `docs/`
  - Milestone docs, runbooks, and spike notes

## Local-Only Files and Folders

The following local files and folders are not committed:

- `.env`
- `keys/`
- `logs/`
- `local_data/shopify/`
- `local_data/shopify_api_spike/`
- `local_data/shopify_bulk_spike/`
- `local_data/shopify_api_landing/`
- `local_data/etsy_api_spike/`

Local secrets and OAuth tokens stay outside version control.

## Airflow and Local Development

Local Airflow runs through Docker Compose.

Current services include:

- `postgres`
- `airflow-apiserver`
- `airflow-scheduler`
- `airflow-dag-processor`
- `airflow-init`

Current Docker/Airflow support files include:

- `docker-compose.yml`
- `Dockerfile.airflow`
- `airflow/requirements.txt`
- `.env.example`
- `.dockerignore`

Local GCP authentication uses:

- `keys/gcp-sa.json`
- `GOOGLE_APPLICATION_CREDENTIALS`
- environment-backed `google_cloud_default` Airflow connection

Shopify and Etsy credentials are passed through local `.env`.

## Current DAGs

### Active / operational DAGs

- `mm_bigquery_refresh_mvp`
  - Rebuilds staging, marts, analysis, dashboard-facing views, and validation from current canonical raw/latest tables.

- `mm_shopify_api_canonical_refresh_mvp`
  - Master automated Shopify API canonical refresh DAG.

- `mm_etsy_recent_refresh_mvp`
  - Runs rolling recent Etsy landing, promotes recent candidates to latest tables, validates Etsy landing, rebuilds Etsy staging/marts/dimensions, validates Etsy models, rebuilds cross-channel revenue outputs, rebuilds cross-channel dashboard views, and validates outputs.

- `mm_shopify_raw_load_and_refresh_mvp`
  - Manual Shopify CSV fallback load plus warehouse refresh.

### Historical / backfill DAGs

- `mm_etsy_historical_backfill_mvp`
  - Completed Etsy historical receipt and transaction backfill.
  - Paused after completion.

- `mm_etsy_historical_payments_backfill_mvp`
  - Completed Etsy historical payment enrichment.
  - Paused after completion.

### Shopify helper/spike DAGs

- `mm_shopify_api_extract_spike`
- `mm_shopify_bulk_operation_spike`
- `mm_shopify_api_products_landing_mvp`
- `mm_shopify_api_customers_landing_mvp`
- `mm_shopify_api_orders_landing_mvp`

## Shopify Pipeline

The Shopify pipeline supports both CSV fallback ingestion and API-backed canonical refresh.

The current automated Shopify flow is:

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

Canonical raw Shopify tables:

- `raw.shopify_orders`
- `raw.shopify_products`
- `raw.shopify_customers`

Shopify API canonical refresh preserves historical CSV-derived order history before the API cutover date and uses API-forward rows on or after the cutover date.

API-unavailable legacy CSV fields are retained as nullable fields where needed to preserve downstream compatibility.

Rollback backup tables include:

- `raw_load.shopify_products_pre_automated_refresh_backup_latest`
- `raw_load.shopify_customers_pre_automated_refresh_backup_latest`
- `raw_load.shopify_orders_pre_automated_refresh_backup_latest`

Operational runbook:

- `docs/operations/shopify_api_canonical_refresh_runbook.md`

## Etsy Pipeline

The Etsy pipeline supports:

- OAuth-based local API access
- receipt landing
- receipt transaction landing
- receipt payment landing
- historical receipt and transaction backfill
- historical payment enrichment
- rolling recent refresh orchestration
- Etsy-native staging models
- Etsy-native fact and dimension models

Core Etsy grains:

- receipts = order/header grain
- receipt transactions = order-item grain
- receipt payments = payment/fee/net grain
- ledger entries = payout/accounting reconciliation grain

Current latest Etsy landing tables:

- `raw_load.etsy_receipts_api_latest`
- `raw_load.etsy_receipt_transactions_api_latest`
- `raw_load.etsy_receipt_payments_api_latest`

The current Etsy recent refresh flow is:

Etsy recent API landing
-> recent candidate promotion to latest
-> Etsy landing validation gate
-> Etsy staging models
-> Etsy staging validation gate
-> Etsy fact models
-> Etsy mart validation gate
-> Etsy dimension models
-> Etsy dimension validation gate
-> fct_cross_channel_orders
-> cross-channel revenue views
-> dashboard revenue views
-> cross-channel validation gate
-> dashboard validation gate

Known Etsy API/source behaviors:

- some receipt payment endpoint calls return Etsy 404s
- some Etsy transaction rows have blank SKUs
- Etsy payment net may reflect deductions beyond the visible fee amount, including tax and marketplace payment behavior

## Core Modeling Principles

- Trusted dates are the default standard for business-facing analysis.
- `customer_email` is the practical Shopify customer key.
- `order_number` is the practical Shopify business-facing order key.
- Etsy order identity starts from `receipt_id`.
- Etsy order-item identity starts from `transaction_id`.
- Etsy customer identity starts from `buyer_user_id`.
- Etsy listing/product identity starts from `listing_id`.
- Cross-channel models use channel-aware keys.
- Shared semantic logic lives upstream in reusable marts models.
- Dashboard models should not re-implement product-family identity or customer identity logic.
- Raw ingestion, landing, canonical raw rebuild, promotion, semantic modeling, BI outputs, and validation are separate concerns.
- Local CSV file-drop ingestion remains the known-good Shopify fallback.
- Shopify API ingestion is the automated canonical refresh path.
- Etsy API ingestion has historical landing/backfill plus ongoing recent refresh orchestration.

## Current Core Models

### Shopify marts

- `marts.dim_customers`
- `marts.dim_products_historical`
- `marts.dim_products`
- `marts.product_family_map`
- `marts.dim_product_families`
- `marts.fct_orders`
- `marts.fct_order_items`

### Etsy staging

- `staging.stg_etsy_receipts`
- `staging.stg_etsy_receipt_transactions`
- `staging.stg_etsy_receipt_payments`

### Etsy marts

- `marts.fct_etsy_orders`
- `marts.fct_etsy_order_items`
- `marts.fct_etsy_payments`
- `marts.dim_etsy_customers`
- `marts.dim_etsy_listings`

### Cross-channel mart

- `marts.fct_cross_channel_orders`

This model combines mature Shopify order facts with Etsy receipt/payment landing data at one row per channel order.

It uses channel-aware keys such as:

- `shopify:<order_number>`
- `etsy:<receipt_id>`

The model intentionally does not solve full cross-channel customer identity resolution or product-family harmonization.

## Analysis and Dashboard Views

### Existing analysis views

Examples include:

- `marts.anl_daily_kpi_summary`
- `marts.anl_monthly_business_summary`
- `marts.anl_customer_summary`
- `marts.anl_family_summary`
- `marts.anl_product_performance_by_family`
- `marts.anl_product_revenue_monthly_by_family`
- `marts.anl_product_family_recent_trends`
- `marts.anl_product_family_customer_mix`
- `marts.cross_channel_revenue_daily`
- `marts.cross_channel_revenue_daily_pivot`

### Dashboard-facing views

Milestone 48 added a dashboard contract layer:

- `marts.anl_dashboard_revenue_daily`
- `marts.anl_dashboard_revenue_monthly`
- `marts.anl_dashboard_channel_daily`
- `marts.anl_dashboard_product_family_summary`
- `marts.anl_dashboard_customer_health`

These views power the private Looker Studio Business Dashboard MVP.

## Business Dashboard MVP

The first dashboard MVP is built in Looker Studio using curated BigQuery views.

Dashboard pages:

1. Executive Overview
2. Monthly Business Trend
3. Product Families
4. Customer Health

Primary executive KPI:

- Post-Refund Revenue

Other executive metrics include:

- Gross Revenue
- Completed Orders
- Units Sold
- AOV
- Shopify revenue
- Etsy revenue
- Etsy fees where available

Product Families and Customer Health are intentionally Shopify-only in the current dashboard. Cross-channel product-family harmonization and customer identity resolution are deferred.

The live dashboard is not linked from this public repository because it contains real business revenue, order, product, and customer data.

## Revenue Semantics

The dashboard uses conservative revenue definitions.

- Gross Revenue
  - customer/order revenue before refunds

- Post-Refund Revenue
  - revenue after refunds
  - primary cross-channel business KPI for the dashboard

- Etsy Fees Recorded
  - Etsy fee amount where receipt payment records are available

- Channel Payment Net
  - channel-reported payment net where available
  - not treated as fully reconciled accounting net

The project does not yet model full profit because COGS, ad spend, payout reconciliation, and complete accounting treatment are deferred.

## Validation

Validation exists across multiple layers, including:

- Shopify marts
- Shopify analysis outputs
- product-family models
- Etsy landing
- Etsy staging
- Etsy marts
- Etsy dimensions
- cross-channel revenue
- dashboard MVP outputs

Etsy validation files:

- `sql/validation/etsy_staging_validation.sql`
- `sql/validation/etsy_marts_validation.sql`
- `sql/validation/etsy_dimensions_validation.sql`

Dashboard validation file:

- `sql/validation/dashboard_mvp_validation.sql`

## Milestone History

### Milestone 44 - Etsy Source Integration Spike

- Registered and approved Etsy Open API application.
- Completed OAuth flow.
- Confirmed access to shop/user lookup, receipts, transactions, payments, and ledger entries.
- Created local Etsy API probe script and spike documentation.

### Milestone 45 - Etsy Orders Landing MVP

- Added Etsy receipt, transaction, and payment landing.
- Created latest landing tables in `raw_load`.
- Added Etsy landing validation.
- Kept Etsy isolated in `raw_load`.

### Milestone 46 - Cross-Channel Revenue Model MVP

- Added `fct_cross_channel_orders`.
- Added daily cross-channel revenue analysis outputs.
- Combined Shopify and Etsy revenue into first cross-channel model.
- Preserved channel-aware keys.

### Milestone 47A - Etsy Historical Receipts and Transactions Backfill

- Backfilled Etsy receipts and transactions to match the trusted Shopify modeling window beginning `2021-01-31`.
- Created historical backfill state table.
- Completed all receipt/transaction chunks.
- Promoted deduplicated candidates into latest Etsy landing tables.

### Milestone 47B - Etsy Historical Payments Enrichment

- Backfilled Etsy receipt payment records.
- Added payment-specific state tracking.
- Tracked skipped 404 receipts separately.
- Promoted payment candidates into latest Etsy payment table.
- Added active Etsy recent refresh DAG.
- Paused historical Etsy backfill DAGs after completion.

### Milestone 48 - Business Dashboard MVP

- Added dashboard-facing BigQuery views.
- Added dashboard validation.
- Wired dashboard views into Airflow refresh DAGs.
- Fixed upstream product-family display-name cleanup.
- Built the first private Looker Studio dashboard MVP.
- Established Post-Refund Revenue as the primary cross-channel executive revenue KPI.

### Milestone 49 - Etsy Staging and Marts MVP

- Added Etsy-native staging models.
- Added Etsy-native order, order-item, and payment facts.
- Added Etsy-native customer and listing dimensions.
- Added Etsy staging, mart, and dimension validations.
- Wired Etsy models and validations into the main and recent-refresh DAGs.
- Preserved cross-channel customer and product harmonization as future work.

## Current Roadmap

Near-term roadmap:

- Milestone 50 - Cross-channel customer and product hardening

Deferred future work:

- cross-channel product-family harmonization
- cross-channel customer identity resolution
- Etsy listing catalog ingestion
- Etsy payout/accounting reconciliation
- COGS/profit modeling
- ad spend integration
- Faire integration
- dbt migration
- Snowflake version
- AI/RAG interface over the warehouse

## Common Commands

Run the main warehouse refresh DAG from Airflow UI or CLI:

    docker compose exec airflow-scheduler airflow dags trigger mm_bigquery_refresh_mvp

Run the Etsy recent refresh DAG:

    docker compose exec airflow-scheduler airflow dags trigger mm_etsy_recent_refresh_mvp

Check DAG imports:

    docker compose exec airflow-scheduler airflow dags list
    docker compose exec airflow-scheduler airflow dags list-import-errors

Run Etsy validations manually:

    bq query --use_legacy_sql=false < sql/validation/etsy_staging_validation.sql
    bq query --use_legacy_sql=false < sql/validation/etsy_marts_validation.sql
    bq query --use_legacy_sql=false < sql/validation/etsy_dimensions_validation.sql

Run dashboard validation manually:

    bq query --use_legacy_sql=false < sql/validation/dashboard_mvp_validation.sql

Run Python compile checks on DAGs:

    python -m py_compile dags/mm_bigquery_refresh_mvp.py
    python -m py_compile dags/mm_etsy_recent_refresh_mvp.py
    python -m py_compile dags/mm_shopify_raw_load_and_refresh_mvp.py

Remove local Python cache files:

    find dags -name "__pycache__" -type d -prune -exec rm -rf {} +

## Notes

This is an active learning and portfolio project. The modeling favors explicit, conservative business definitions over premature completeness.

Known boundaries are documented rather than hidden. This is especially important for cross-channel identity, product-family harmonization, tax, Etsy payout behavior, and accounting net revenue.
