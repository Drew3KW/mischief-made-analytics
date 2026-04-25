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
- SQL
- Apache Airflow 3
- Docker Compose
- WSL / Ubuntu local development
- GitHub

## Current warehouse structure

- `raw`: canonical raw source history
- `raw_load`: latest landed source-file imports used for canonical raw rebuild
- `staging`: cleaned and typed source models
- `marts`: dimensional models and fact tables
- `sql/analysis`: business-facing analysis queries and semantic analysis-layer models
- `sql/validation`: QA and validation queries
- `docs/milestones`: milestone writeups documenting major project steps
- `dags/`: Airflow orchestration DAGs

## Current source systems

- Shopify orders export
- Shopify products export
- Shopify customers export

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

### Supporting analysis / review queries

- `product_family_recent_trends_review.sql`
- `customer_order_behavior_review.sql`
- `customer_recency_segments_review.sql`
- `customer_cohort_retention_review.sql`
- `product_family_customer_mix_review.sql`
- `customer_rfm_segments_review.sql`
- `daily_kpi_summary_review.sql`
- `monthly_business_summary_review.sql`
- `customer_summary_review.sql`
- `family_summary_review.sql`

### Supporting validation

- `customer_order_behavior_validation.sql`
- `customer_recency_segments_validation.sql`
- `customer_cohort_retention_validation.sql`
- `product_family_customer_mix_validation.sql`
- `customer_rfm_segments_validation.sql`
- `daily_kpi_summary_validation.sql`
- `monthly_business_summary_validation.sql`
- `customer_summary_validation.sql`
- `family_summary_validation.sql`

### Machine-readable Airflow assertions

The Airflow DAGs include machine-readable validation tasks backed by BigQuery assertion SQL under:

- `sql/validation/assertions/`

These assertions act as pass / fail data quality gates at the end of the orchestrated pipeline.

## Current orchestration layer

### Airflow Docker Compose MVP

The project now uses Docker Compose as the preferred local Airflow runtime.

Current Docker Compose services:

- `postgres`
- `airflow-apiserver`
- `airflow-scheduler`
- `airflow-dag-processor`
- `airflow-init`

The Dockerized setup replaced the earlier `airflow standalone` local runtime after standalone became unstable during iterative testing.

Docker Compose provides a more explicit local development environment with:

- Postgres-backed Airflow metadata
- reproducible Airflow dependencies
- mounted repo folders for DAGs, SQL, data files, logs, and keys
- stable local UI / scheduler / DAG processor services
- environment-based GCP authentication

### Current Airflow DAGs

The project includes two local Apache Airflow DAGs:

- `mm_bigquery_refresh_mvp`
- `mm_shopify_raw_load_and_refresh_mvp`

### `mm_bigquery_refresh_mvp`

Current refresh DAG scope:

- supports both manual trigger and daily scheduled refresh
- refreshes `staging` -> `marts` -> `analysis` -> `validation`
- executes checked-in repo SQL files in BigQuery
- includes a machine-readable validation task group using BigQuery `ASSERT`
- uses lightweight retry settings for local resiliency

### `mm_shopify_raw_load_and_refresh_mvp`

Current raw-load DAG scope:

- supports manual local Shopify CSV ingestion
- expects local source files under:
  - `local_data/shopify/customers.csv`
  - `local_data/shopify/products.csv`
  - `local_data/shopify/orders.csv`
- loads latest source files into:
  - `raw_load.shopify_customers_latest`
  - `raw_load.shopify_products_latest`
  - `raw_load.shopify_orders_latest`
- rebuilds canonical raw history tables:
  - `raw.shopify_customers`
  - `raw.shopify_products`
  - `raw.shopify_orders`
- then continues through:
  - `staging`
  - `marts`
  - `analysis`
  - `validation`

Current raw-load DAG flow:

- `check_input_files`
- `raw_load`
- `raw_rebuild`
- `staging`
- `marts`
- `analysis`
- `validation`

## Local Docker Airflow workflow

The project uses Docker Compose to run a local Airflow 3 environment.

Docker provides a more stable and reproducible local orchestration setup than `airflow standalone`.

### Prerequisites

- Docker Desktop for Windows
- WSL integration enabled in Docker Desktop
- GCP service account key available locally
- Shopify CSV exports available locally

### Local-only files

The following files are required for local execution but should not be committed:

```text
keys/gcp-sa.json
local_data/shopify/*.csv
logs/
```

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

Local login:

```text
admin / admin
```

### Run the pipeline

Most local DAG work can be done from the Airflow UI.

Current DAGs:

- `mm_bigquery_refresh_mvp`
  - refreshes the existing warehouse from current raw tables
- `mm_shopify_raw_load_and_refresh_mvp`
  - loads local Shopify CSV files
  - rebuilds canonical raw tables
  - refreshes staging, marts, analysis, and validation layers

To run a DAG:

1. open the Airflow UI
2. choose the DAG
3. click the manual trigger button
4. monitor the run in Grid or Graph view
5. inspect task logs from the UI if anything fails

### Stop Airflow

From the repo root:

```bash
docker compose down
```

If services were renamed or stale containers remain:

```bash
docker compose down --remove-orphans
```

## Key modeling lessons so far

- Shopify raw exports are messy and best ingested as strings first
- Order grain and line-item grain must be validated carefully
- `order_number` is the most practical business-facing order key
- `customer_email` is the current practical customer key
- Current product exports do not fully represent historical sold products
- Historical product coverage required a dedicated product spine
- Historical product family analysis requires careful normalization of SKU and product name logic
- Business-facing family rollups depend on choosing one canonical family name per family key
- Trusted historical trend analysis requires filtering out suspect order-timing records
- Customer behavior modeling should be built from the order fact as the source of truth
- Customer descriptive attributes may be imperfect, but customer email remains the trusted analytical key
- Cohort analysis is especially sensitive to date quality, so trusted-date filtering matters at cohort assignment time, not just in downstream trend reporting
- When business logic becomes reused across multiple analysis models, it should be promoted into shared warehouse models rather than repeated downstream
- Shared semantic models make downstream analysis views shorter, more maintainable, and easier to extend
- Shared family models should define both family identity and business-facing reporting eligibility
- Non-core families can remain available in the warehouse while still being excluded consistently from core summary and analysis layers
- Raw ingestion and raw rebuild are separate concerns: latest landed files should not automatically overwrite canonical source history
- Source-file schema drift is a real ingestion concern and should be handled deliberately at the raw rebuild boundary
- Local orchestration runtime state should be reproducible and disposable where practical
- Docker Compose provides a more stable local orchestration foundation than `airflow standalone`

## Major project milestones so far

### Historical product coverage

A major issue was uncovered when order items joined poorly to the current product dimension.

Investigation showed that historical sold products had often been deleted from Shopify, and some sold rows had blank SKUs. This was solved by building `dim_products_historical`, which restored complete product coverage for historical sales analysis.

### Product family rollups

Analysis Pack v1 work uncovered additional historical naming issues, including:

- size suffixes leaking into family-level names
- generic names over-grouping unrelated products
- multiple family names appearing for the same family key

These were addressed by:

- refining family-key logic
- improving canonical family naming
- building monthly family revenue outputs using trusted dates
- adding recent-trend analysis at product family grain

### Shared product-family models

As product-family logic became a repeated semantic dependency across the project, it was promoted into shared marts models:

- `product_family_map`
- `dim_product_families`

This centralized product-family assignment, canonical naming, and business-facing family reporting eligibility, reduced repeated downstream regex logic, and created a reusable family layer for future analysis.

### Customer order behavior

Analysis Pack v1 expanded into customer-level behavior modeling with a reusable customer-grain analysis view supporting:

- repeat vs one-time customer analysis
- average order value analysis
- top-customer identification
- cancellation behavior review
- refund behavior review

This work established a customer behavior layer built from `fct_orders`, with completed-order metrics based on non-cancelled orders and customer email used as the practical business key.

### Customer lifecycle, retention, and segmentation

Analysis Pack v1 now also includes:

- customer recency segmentation
- customer cohort retention
- customer RFM-style segmentation

This extends the project from static customer summaries into lifecycle, retention, and segmentation analysis, helping answer:

- which customers are active, warming, cooling, or lapsed
- whether customer cohorts return over time
- how quickly cohorts decay after acquisition
- how much revenue cohorts generate across later lifecycle months
- which customers are loyal, high-value, recent one-time buyers, or win-back candidates

### Product-family customer behavior

Analysis Pack v1 also includes:

- product-family customer mix analysis

This connects product-family performance to customer behavior, helping answer:

- which families attract more repeat customers
- which families appear more often in first orders
- which families are associated with higher-value customers
- which families look more acquisition-oriented versus loyalty-oriented

### Dashboard-ready KPI summary layer

The next phase of Analysis Pack v1 began the project’s summary layer with `anl_daily_kpi_summary`, a one-row-per-day business summary built for BI consumption.

This layer consolidates core daily business metrics including:

- submitted, completed, and cancelled orders
- customers purchasing each day
- new vs returning customers
- units sold
- gross revenue, refunded amount, and net revenue after refunds
- average order value and core daily rates

This creates a cleaner semantic bridge between detailed warehouse models and future dashboards.

### Monthly business summary layer

The summary layer was extended with `anl_monthly_business_summary`, a one-row-per-month rollup built on top of `anl_daily_kpi_summary`.

This layer consolidates monthly business performance into a cleaner reporting view including:

- submitted, completed, and cancelled orders
- customer totals and new vs returning customer mix
- units sold
- gross revenue, refunded amount, and net revenue after refunds
- blended monthly KPIs such as average order value and average units per order
- month-over-month changes in revenue, orders, and customers

This makes the warehouse more useful for business-owner reporting and provides a stronger monthly semantic layer for future dashboards.

### Monthly customer summary layer

The summary layer was extended again with `anl_customer_summary`, a one-row-per-month customer reporting layer built to support BI-friendly customer mix and lifecycle reporting.

This layer consolidates monthly customer performance including:

- active customers
- new vs returning customers
- one-time vs repeat customer base composition
- recency / lifecycle mix
- value / segment mix
- customer-focused month-over-month changes

### Monthly family summary layer

The summary layer now also includes `anl_family_summary`, a one-row-per-month-per-family reporting layer built for BI-friendly family performance analysis.

This layer consolidates monthly family performance including:

- family revenue
- orders containing each family
- units sold
- monthly family customer counts
- new vs returning family customers
- family share of monthly business
- month-over-month family trend fields
- BI-friendly family tiers and trend status

### Airflow local MVP orchestration

With Analysis Pack v1 effectively complete, the project’s next phase moved from standalone SQL development into orchestration.

This milestone introduced a first working local Airflow DAG that can rebuild the warehouse in dependency order across:

- `staging`
- `marts`
- `analysis`

This established a real orchestration layer for the project and created a foundation for validation, refresh scheduling, raw load automation, and multi-source pipeline growth.

### Airflow validation MVP

The orchestration layer was then extended with a machine-readable validation task group.

This milestone added assertion SQL files under `sql/validation/assertions/` and integrated them into the DAG so warehouse refreshes now end with explicit pass / fail validation checks for key models.

This improved both warehouse trust and portfolio realism by adding a first true data-quality gate to the pipeline.

### Airflow scheduled refresh MVP

The Airflow MVP was then extended from manual-only execution into scheduled recurring refresh.

This milestone added a daily schedule and lightweight retry settings to the local DAG while retaining simple local-development safeguards such as:

- `catchup=False`
- `max_active_runs=1`

The scheduled DAG was validated through both manual execution and the first successful automatic scheduled run, confirming that the local Airflow layer now supports refresh, validation, and recurring execution together.

### Airflow raw CSV load MVP

The orchestration layer was extended into local raw source ingestion.

This milestone added a second local Airflow DAG that:

- loads current Shopify CSV exports into `raw_load`
- rebuilds canonical `raw` history tables
- refreshes the downstream warehouse
- runs machine-readable validation at the end

This made the project substantially more realistic as an analytics engineering portfolio piece by moving beyond warehouse-only refreshes into a source-ingestion-plus-refresh workflow.

### Airflow Docker Compose MVP

The local Airflow runtime was migrated from `airflow standalone` to Docker Compose.

This milestone added a Dockerized Airflow 3 environment with:

- Postgres metadata database
- Airflow API server / UI
- scheduler
- DAG processor
- initialization service
- custom Airflow image
- mounted repo folders
- mounted local GCP service account key
- environment-backed BigQuery connection

The full raw-load + warehouse refresh + validation DAG was successfully run end to end inside Docker.

This created a more stable and reproducible local orchestration foundation for continued ingestion, BI, and future multi-source work.

## Current focus

Current work is centered on strengthening the project’s orchestration and local development foundation after completing Analysis Pack v1.

The project now has:

- a complete Analysis Pack v1 foundation
- dashboard-ready summary layers
- local Airflow warehouse orchestration
- machine-readable validation tasks
- daily scheduled warehouse refresh
- local raw Shopify CSV ingestion and canonical raw rebuild
- Docker Compose-based Airflow 3 runtime

The next likely engineering focus is continuing to strengthen ingestion, documentation, and operational polish while preparing for broader source expansion and BI/dashboard work.

## Future roadmap

- generate real business insights for Mischief Made from the warehouse
- BI dashboarding
- broader raw CSV load orchestration
- additional source integration:
  - Etsy
  - Faire
  - Etsy Ads
  - Pinterest Ads
- cross-channel revenue and marketing analysis
- eventual migration to dbt + Snowflake
