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
- `dim_product_families`
- `product_family_map`
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

### Supporting analysis / review queries
- `product_family_recent_trends_review.sql`
- `customer_order_behavior_review.sql`
- `customer_recency_segments_review.sql`
- `customer_cohort_retention_review.sql`

### Supporting validation
- `customer_order_behavior_validation.sql`
- `customer_recency_segments_validation.sql`
- `customer_cohort_retention_validation.sql`

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
- building trusted monthly family revenue outputs
- adding recent-trend analysis at product family grain

### Customer order behavior
Analysis Pack v1 expanded into customer-level behavior modeling with a reusable customer-grain analysis view supporting:
- repeat vs one-time customer analysis
- average order value analysis
- top-customer identification
- cancellation behavior review
- refund behavior review

This work established a customer behavior layer built from `fct_orders`, with completed-order metrics based on non-cancelled orders and customer email used as the practical business key.

### Customer lifecycle and retention
Analysis Pack v1 now also includes:
- customer recency segmentation
- trusted-dates customer cohort retention

This extends the project from static customer summaries into lifecycle and retention analysis, helping answer:
- which customers are active, warming, cooling, or lapsed
- whether customer cohorts return over time
- how quickly cohorts decay after acquisition
- how much revenue cohorts generate across later lifecycle months

## Current focus

Current work is centered on Analysis Pack v1, which now includes both product-family and customer analysis:
- family-level product performance
- shared product-family modeling for reusable downstream family analysis
- trusted monthly product-family revenue trends
- recent family trend classification
- customer order behavior
- customer recency segmentation
- trusted-dates customer cohort retention
- review and validation queries for business-facing analysis

## Future roadmap

- generate real business insights for Mischief Made from the warehouse
- expand analysis into:
  - customer x product-family mix analysis
  - simple RFM-style segmentation
  - dashboard-ready KPI and summary layers
- BI dashboarding
- additional source integration:
  - Etsy
  - Faire
  - Etsy Ads
  - Pinterest Ads
- cross-channel revenue and marketing analysis
- eventual migration to dbt + Snowflake
