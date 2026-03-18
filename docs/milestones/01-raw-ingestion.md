# Milestone: Raw Shopify Ingestion Strategy

## Summary
This milestone established the raw ingestion layer for the Mischief Made warehouse in BigQuery. 
Shopify CSV exports for orders, products, and customers were loaded into the `raw` dataset with all columns stored as `STRING`, creating a stable landing zone for messy source data.

## Problem
Shopify exports were not analytics-ready. They contained inconsistent null handling, columns with spaces, repeated order-level fields, and varying record quality. 
Applying strict typing during ingestion would have increased the risk of load failures and made debugging harder.

## Investigation
Initial profiling showed that:
- the orders export was at line-item grain, not order grain
- nulls and blanks were inconsistent
- order-level fields were repeated across rows
- BigQuery required backticks for some source column names

These findings showed that the raw layer needed to prioritize stability over cleanup.

## Decision
All source files were loaded into BigQuery as-is, with every field stored as `STRING`.

This approach was used for:
- `raw.shopify_orders`
- `raw.shopify_products`
- `raw.shopify_customers`

Cleaning, typing, and business logic were deferred to the staging layer.

## Validation
The raw tables loaded successfully and preserved the source data without type-related ingestion failures. Later staging work confirmed that postponing typing was the right choice.

## Business impact
This created a dependable foundation for the warehouse and reduced the risk of fragile ingestion failures on messy Shopify exports.

## Portfolio significance
This milestone shows a practical analytics engineering principle: raw ingestion should optimize for source fidelity and pipeline stability, with cleanup and typing handled downstream.
