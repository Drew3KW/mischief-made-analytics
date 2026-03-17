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
- `sql/analysis`: business-facing analysis queries
- `sql/validation`: QA and validation queries

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

## Key modeling lessons so far

- Shopify raw exports are messy and best ingested as strings first
- Order grain and line-item grain must be validated carefully
- `order_number` is the most practical business-facing order key
- `customer_email` is the current practical customer key
- Current product exports do not fully represent historical sold products
- Historical product coverage required a dedicated product spine

## Major project milestone

A major issue was uncovered when order items joined poorly to the current product dimension. Investigation showed that historical sold products had often been deleted from Shopify, and some sold rows had blank SKUs. This was solved by building `dim_products_historical`, which restored complete product coverage for historical sales analysis.

## Next phase

Analysis Pack v1:
- revenue by product
- units sold by product
- average order value
- repeat vs one-time customers
- refund patterns
- product mix analysis

## Future roadmap
- real business insight generation for Mischief Made
- BI dashboarding
- additional source integration:
  - Etsy
  - Faire
  - Etsy Ads
  - Pinterest Ads
- cross-channel revenue and marketing analysis
- eventual migration to dbt + Snowflake
