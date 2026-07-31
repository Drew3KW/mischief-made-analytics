# Mischief Made Analytics

Mischief Made Analytics is a BigQuery and Airflow analytics engineering project for Mischief Made, an apparel business selling through Shopify, Etsy, and other channels.

The project serves two purposes:

1. Build a real decision-support system for the business.
2. Serve as a flagship analytics engineering / data engineering portfolio project.

The current system ingests Shopify and Etsy data, models trusted business metrics in BigQuery, validates key outputs, orchestrates refreshes with Airflow, and powers a private Looker Studio business dashboard.

## Current Stack

* BigQuery
* SQL
* Shopify CSV exports
* Shopify Admin API
* Etsy Open API
* Apache Airflow 3
* Docker Compose
* WSL / Ubuntu local development
* VS Code
* GitHub
* Looker Studio

## Project Status

The warehouse currently supports:

* Shopify CSV fallback ingestion
* Shopify API landing and canonical raw refresh
* Etsy API historical landing/backfill
* Etsy payment enrichment
* Etsy recent refresh orchestration
* Shopify staging, marts, and analysis models
* Etsy staging, marts, and dimension models
* Cross-channel Shopify/Etsy revenue modeling
* Conservative cross-channel customer and product-family hardening
* Cross-channel order item profitability foundation
* Manual COGS mapping and product-family override support
* Product profitability summary and monthly analysis views
* Dashboard-facing BigQuery views
* Private Looker Studio Business Dashboard MVP
* Validation across source, staging, marts, analysis, cross-channel, dashboard, and profitability layers
* Product and channel profitability KPI, ranking, monthly trend, and coverage-audit views
* Qualified product-family gross-margin rankings with explicit eligibility rules

## Repository Structure

* `dags/` - Airflow DAGs
* `scripts/` - Python API extraction, landing, and backfill scripts
* `sql/raw/` - Raw rebuild, candidate, promotion, and rollback SQL
* `sql/staging/` - Staging models
* `sql/marts/` - Facts, dimensions, bridges, and shared semantic models
* `sql/analysis/` - Business-facing analysis, audit, and dashboard views
* `sql/validation/` - Validation queries and assertion checks
* `docs/` - Milestone docs, runbooks, and spike notes

## Local-Only Files

The following files and folders are intentionally not committed:

* `.env`
* `keys/`
* `logs/`
* `local_data/shopify/`
* `local_data/shopify_api_spike/`
* `local_data/shopify_bulk_spike/`
* `local_data/shopify_api_landing/`
* `local_data/etsy_api_spike/`
* `local_data/cogs/`

Local secrets, service-account keys, OAuth tokens, downloaded API samples, and private COGS inputs stay outside version control.

## Airflow DAGs

### Active DAGs

* `mm_bigquery_refresh_mvp` - Rebuilds staging, marts, cross-channel bridge/dimension models, COGS/profitability models, analysis views, dashboard views, and validation.
* `mm_shopify_api_canonical_refresh_mvp` - Runs the automated Shopify API canonical raw refresh.
* `mm_etsy_recent_refresh_mvp` - Runs rolling recent Etsy landing, promotes latest Etsy tables, rebuilds Etsy models, rebuilds cross-channel hardening models, and validates downstream outputs.
* `mm_shopify_raw_load_and_refresh_mvp` - Manual Shopify CSV fallback load plus warehouse refresh.

### Paused Historical DAGs

* `mm_etsy_historical_backfill_mvp` - Completed Etsy historical receipt and transaction backfill.
* `mm_etsy_historical_payments_backfill_mvp` - Completed Etsy historical payment enrichment.

### Shopify Helper / Spike DAGs

* `mm_shopify_api_extract_spike`
* `mm_shopify_bulk_operation_spike`
* `mm_shopify_api_products_landing_mvp`
* `mm_shopify_api_customers_landing_mvp`
* `mm_shopify_api_orders_landing_mvp`

## Shopify Pipeline

The Shopify pipeline supports both CSV fallback ingestion and API-backed canonical refresh.

Current automated flow:

Shopify API landing -> API landing validation -> API raw candidates -> API raw candidate validation -> hybrid raw candidates -> hybrid validation -> canonical raw backup -> canonical raw replacement -> warehouse refresh -> canonical raw replacement validation

Canonical Shopify raw tables:

* `raw.shopify_orders`
* `raw.shopify_products`
* `raw.shopify_customers`

The Shopify API path preserves CSV-derived order history before the API cutover date and uses API-forward rows on or after the cutover date.

API-unavailable legacy fields are retained as nullable fields where needed for downstream compatibility.

Rollback backup tables are maintained in `raw_load`.

Operational runbook:

* `docs/operations/shopify_api_canonical_refresh_runbook.md`

## Etsy Pipeline

The Etsy pipeline supports:

* OAuth-based API access
* receipt landing
* receipt transaction landing
* receipt payment landing
* historical receipt and transaction backfill
* historical payment enrichment
* rolling recent refresh orchestration
* Etsy-native staging, fact, and dimension models

Core Etsy grains:

* receipts = order/header grain
* receipt transactions = order-item grain
* receipt payments = payment/fee/net grain
* ledger entries = payout/accounting reconciliation grain

Latest Etsy landing tables:

* `raw_load.etsy_receipts_api_latest`
* `raw_load.etsy_receipt_transactions_api_latest`
* `raw_load.etsy_receipt_payments_api_latest`

Known Etsy source behaviors:

* some receipt payment endpoint calls return Etsy 404s
* some Etsy transaction rows have blank SKUs
* Etsy receipt responses currently include the `buyer_email` key but return null buyer email values
* Etsy payment net may reflect deductions beyond visible Etsy fees, including tax and marketplace payment behavior

## Core Modeling Principles

* Trusted dates are the default standard for business-facing analysis.
* `customer_email` is the practical Shopify customer key.
* `order_number` is the practical Shopify business-facing order key.
* Etsy order identity starts from `receipt_id`.
* Etsy order-item identity starts from `transaction_id`.
* Etsy customer identity starts from `buyer_user_id`.
* Etsy listing/product identity starts from `listing_id`.
* Cross-channel models use channel-aware keys.
* Shared semantic logic lives upstream in reusable marts models.
* Dashboard models should not re-implement core product-family or customer identity logic.
* Raw ingestion, landing, promotion, semantic modeling, validation, and BI outputs are separate concerns.
* Harmonization is conservative, explicit, and auditable.
* Unresolved matches remain visible rather than being forced into low-confidence matches.
* COGS and profitability models expose coverage and resolution status rather than hiding missing or review-needed cost data.

## Core Models

### Shopify Marts

* `marts.dim_customers`
* `marts.dim_products_historical`
* `marts.dim_products`
* `marts.product_family_map`
* `marts.dim_product_families`
* `marts.fct_orders`
* `marts.fct_order_items`

### Etsy Marts

* `marts.fct_etsy_orders`
* `marts.fct_etsy_order_items`
* `marts.fct_etsy_payments`
* `marts.dim_etsy_customers`
* `marts.dim_etsy_listings`

### Cross-Channel Marts

* `marts.fct_cross_channel_orders`
* `marts.fct_cross_channel_order_items`
* `marts.cross_channel_customer_bridge`
* `marts.cross_channel_product_family_bridge`
* `marts.dim_cross_channel_customers`
* `marts.dim_cross_channel_product_families`

`marts.fct_cross_channel_orders` combines Shopify and Etsy order facts at one row per channel order using channel-aware keys such as:

* `shopify:`
* `etsy:`

`marts.fct_cross_channel_order_items` combines Shopify and Etsy order item facts at one row per channel order item and adds product-family, customer, COGS, and estimated gross profit fields.

The cross-channel bridge and dimension models provide a conservative first-pass hardening layer for customer and product-family semantics.

### COGS and Profitability Models

* `marts.product_cogs_map`
* `marts.product_family_cogs_map`
* `marts.product_name_type_cogs_map`
* `marts.product_family_cogs_override_map`
* `marts.anl_product_profitability_summary`
* `marts.anl_product_profitability_monthly`
* `marts.anl_profitability_kpi_summary`
* `marts.anl_product_profitability_rankings`
* `marts.anl_channel_profitability_monthly`
* `marts.anl_product_profitability_coverage_audit`

The COGS and profitability foundation estimates item-level gross profit before fees using a conservative matching ladder:

1. exact SKU match
2. manual product-family override
3. product-family fallback
4. product name/type fallback
5. manual exclusion
6. missing or review status

The model exposes COGS resolution status and coverage fields so profitability reporting remains transparent, especially where older historical products do not have complete COGS coverage. The profitability analysis layer provides monthly channel KPIs, product-family revenue and gross-profit rankings, qualified margin rankings, conservative month-over-month comparisons, and recent-versus-historical COGS coverage auditing. Legacy product-family keys may be consolidated by exact name for reporting, while source-key lineage remains visible.

## Cross-Channel Hardening

The cross-channel hardening layer makes Shopify and Etsy customer/product semantics comparable without forcing unsafe matches.

Customer hardening currently preserves:

* Shopify customers as channel-only identities
* Etsy buyers as unresolved identities because Etsy buyer email is unavailable in the current Etsy API response data

Product-family hardening currently supports:

* Shopify-native product families
* accepted Etsy-to-Shopify product-family matches from SKU-based logic
* Etsy title-pattern review candidates
* unresolved Etsy listings

## Dashboard Views

Dashboard-facing views include:

* `marts.anl_dashboard_revenue_daily`
* `marts.anl_dashboard_revenue_monthly`
* `marts.anl_dashboard_channel_daily`
* `marts.anl_dashboard_product_family_summary`
* `marts.anl_dashboard_customer_health`

These views power a private Looker Studio Business Dashboard MVP.

Dashboard pages:

1. Executive Overview
2. Monthly Business Trend
3. Product Families
4. Customer Health

The live dashboard is not linked from this public repository because it contains real business revenue, order, product, and customer data.

## Revenue Semantics

The dashboard uses conservative revenue definitions:

* Gross Revenue - customer/order revenue before refunds
* Post-Refund Revenue - revenue after refunds; primary cross-channel executive KPI
* Etsy Fees Recorded - Etsy fee amount where receipt payment records are available
* Channel Payment Net - channel-reported payment net where available; not treated as fully reconciled accounting net

The project now includes estimated product-level gross profit before fees using manually maintained COGS inputs. This is not full accounting net profit: channel fees, ad spend, shipping, labor, overhead, payout reconciliation, and complete accounting treatment remain outside the current profit model.

## Validation

Validation exists across:

* Shopify marts
* Shopify analysis outputs
* product-family models
* Etsy landing
* Etsy staging
* Etsy marts
* Etsy dimensions
* cross-channel revenue
* cross-channel customer/product hardening
* COGS and product profitability foundation
* dashboard outputs
* Product and channel profitability reporting

Key validation files include:

* `sql/validation/etsy_staging_validation.sql`
* `sql/validation/etsy_marts_validation.sql`
* `sql/validation/etsy_dimensions_validation.sql`
* `sql/validation/cross_channel_revenue_validation.sql`
* `sql/validation/cross_channel_identity_hardening_validation.sql`
* `sql/validation/profitability_foundation_validation.sql`
* `sql/validation/dashboard_mvp_validation.sql`

## Milestones

Recent completed milestones:

* Milestone 44 - Etsy Source Integration Spike
* Milestone 45 - Etsy Orders Landing MVP
* Milestone 46 - Cross-Channel Revenue Model MVP
* Milestone 47A - Etsy Historical Receipts and Transactions Backfill
* Milestone 47B - Etsy Historical Payments Enrichment
* Milestone 48 - Business Dashboard MVP
* Milestone 49 - Etsy Staging and Marts MVP
* Milestone 50 - Cross-Channel Customer and Product Hardening
* Milestone 51 - COGS and Profitability Foundation
* Milestone 52 - Product & Channel Profitability MVP

Detailed milestone notes live in `docs/milestones/`.

## Current Roadmap

Near-term work:

* Add ad spend integration to support profitability after marketing costs.
* Extend the private Looker Studio dashboard with validated profitability views.
* Continue improving current COGS coverage through explicit manual overrides.
* Add Faire integration.
* Add new BI outputs only when upstream validation supports them.

Deferred future work:

* manual customer matching
* advanced customer identity graph work
* automated fuzzy matching
* Etsy listing catalog ingestion
* Etsy payout/accounting reconciliation
* full accounting net profit modeling
* dbt migration
* Snowflake version
* AI/RAG interface over the warehouse

## Common Commands

Trigger the main warehouse refresh DAG:

```bash
docker compose exec airflow-scheduler airflow dags trigger mm_bigquery_refresh_mvp
```

Trigger the Etsy recent refresh DAG:

```bash
docker compose exec airflow-scheduler airflow dags trigger mm_etsy_recent_refresh_mvp
```

Check DAG imports:

```bash
docker compose exec airflow-scheduler airflow dags list
docker compose exec airflow-scheduler airflow dags list-import-errors
```

Run cross-channel identity hardening validation manually:

```bash
bq query --use_legacy_sql=false < sql/validation/cross_channel_identity_hardening_validation.sql
```

Run dashboard validation manually:

```bash
bq query --use_legacy_sql=false < sql/validation/dashboard_mvp_validation.sql
```

Run profitability foundation validation manually:

```bash
bq query --use_legacy_sql=false < sql/validation/profitability_foundation_validation.sql
```

Run product and channel profitability validation manually:

bq query --use_legacy_sql=false < sql/validation/product_profitability_mvp_validation.sql

Load local COGS inputs manually before refreshing profitability models:

```bash
python scripts/load_product_cogs_manual.py
python scripts/load_product_family_cogs_overrides.py
```

Run Python compile checks on DAGs:

```bash
python -m py_compile dags/mm_bigquery_refresh_mvp.py
python -m py_compile dags/mm_etsy_recent_refresh_mvp.py
python -m py_compile dags/mm_shopify_raw_load_and_refresh_mvp.py
```

Remove local Python cache files:

```bash
find dags -name "__pycache__" -type d -prune -exec rm -rf {} +
```

## Notes

This is an active learning and portfolio project.

The modeling favors explicit, conservative business definitions over premature completeness. Known boundaries are documented rather than hidden, especially for cross-channel identity, product-family harmonization, tax, Etsy payout behavior, COGS coverage, and accounting net revenue.
