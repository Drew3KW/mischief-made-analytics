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
- `dim_customers`
- `fct_order_items`
- `fct_orders`

## Current analysis layer

### Family-level performance and trends
- `anl_product_performance_by_family`
- `anl_product_revenue_monthly_by_family_trusted_dates`
- `anl_product_family_recent_trends_trusted`

### Supporting analysis / review queries
- `product_family_recent_trends_review.sql`

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

## Current focus

Current work is centered on Analysis Pack v1, especially product-family-level analysis:
- family-level product performance
- trusted monthly product-family revenue trends
- recent family trend classification
- review queries for rising, declining, and new/returning families
- drill-down into variant-level drivers for important product families

## Future roadmap

- generate real business insights for Mischief Made from the warehouse
- expand analysis into:
  - average order value
  - repeat vs one-time customers
  - refund / cancellation patterns
  - product mix and assortment analysis
- BI dashboarding
- additional source integration:
  - Etsy
  - Faire
  - Etsy Ads
  - Pinterest Ads
- cross-channel revenue and marketing analysis
- eventual migration to dbt + Snowflake
