# Mischief Made Analytics

BigQuery-based analytics engineering project for Mischief Made, an apparel brand. This project is designed to be both a real business decision-support system and a flagship portfolio project for an analytics engineering / data engineering career pivot.

## Goals

This project serves two purposes:

1. Help Mischief Made make better business decisions
2. Demonstrate real-world analytics engineering skills in a portfolio project

## Current stack

- BigQuery
- Shopify CSV exports
- SQL
- GitHub

## Current warehouse structure

- `raw`: raw source ingestion
- `staging`: cleaned and typed source models
- `marts`: dimensional models and fact tables
- `sql/analysis`: business-facing analysis queries and semantic analysis-layer models
- `sql/validation`: QA and validation queries
- `docs/milestones`: milestone writeups documenting major project steps

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

### Customer x product-family analysis
- `anl_product_family_customer_mix`

### Supporting analysis / review queries
- `product_family_recent_trends_review.sql`
- `customer_order_behavior_review.sql`
- `customer_recency_segments_review.sql`
- `customer_cohort_retention_review.sql`
- `product_family_customer_mix_review.sql`
- `customer_rfm_segments_review.sql`

### Supporting validation
- `customer_order_behavior_validation.sql`
- `customer_recency_segments_validation.sql`
- `customer_cohort_retention_validation.sql`
- `product_family_customer_mix_validation.sql`
- `customer_rfm_segments_validation.sql`

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

## Major project milestones so far

### Historical product coverage
A major issue was uncovered when order items joined poorly to the current product dimension. Investigation showed that historical sold products had often been deleted from Shopify, and some sold rows had blank SKUs. This was solved by building `dim_products_historical`, which restored complete product coverage for historical sales analysis.

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

This centralized product-family assignment and canonical naming, reduced repeated downstream regex logic, and created a reusable family layer for future analysis.

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

* submitted, completed, and cancelled orders
* customers purchasing each day
* new vs returning customers
* units sold
* gross revenue, refunded amount, and net revenue after refunds
* average order value and core daily rates

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

## Current focus

Current work is centered on Analysis Pack v1, which now includes both product-family and customer analysis plus the beginning of a dashboard-ready summary layer:
- family-level product performance
- shared product-family modeling for reusable downstream family analysis
- monthly product-family revenue trends
- recent family trend classification
- customer order behavior
- customer recency segmentation
- customer cohort retention
- product-family customer mix analysis
- customer RFM-style segmentation
- daily KPI summary
- monthly business summary
- review and validation queries for business-facing analysis

## Future roadmap

- generate real business insights for Mischief Made from the warehouse
- expand the summary layer into:
  - customer summary
  - family summary
- BI dashboarding
- ingestion / refresh scheduling
- additional source integration:
  - Etsy
  - Faire
  - Etsy Ads
  - Pinterest Ads
- cross-channel revenue and marketing analysis
- eventual migration to dbt + Snowflake

