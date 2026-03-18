# Milestone: Raw Shopify Ingestion Strategy

## Summary
This milestone established the raw ingestion layer for the Mischief Made analytics warehouse in BigQuery. Shopify CSV exports for orders, products, 
and customers were loaded into the `raw` dataset with all columns stored as `STRING` values first, creating a stable landing zone for messy source data 
and allowing downstream cleaning and typing to happen in the staging layer.

## Problem
Shopify exports are operational extracts, not analytics-ready source tables. They contain messy and inconsistent values, including:
- mixed true `NULL`s and blank strings
- string-like null values
- columns with spaces and special formatting
- repeated order-level fields across multiple line-item rows
- varying levels of completeness across records

Attempting to apply strict typing during ingestion would have increased the risk of load failures 
and made it harder to separate ingestion problems from transformation problems.

## Investigation
Initial profiling of the Shopify exports showed that the source files were not clean enough to treat as trusted analytical inputs.

Important observations included:
- the orders export was actually at line-item grain, not order grain
- order-level attributes were repeated across line items
- null handling was inconsistent across exports
- BigQuery required backticks around source column names containing spaces
- source data included both meaningful blanks and missing values that needed later interpretation

These findings made it clear that raw ingestion needed to prioritize stability and fidelity over early cleanup.

## Decision
The raw ingestion strategy was to load source CSV exports into BigQuery exactly as landed, with all fields stored as `STRING`.

This approach was used for:
- `raw.shopify_orders`
- `raw.shopify_products`
- `raw.shopify_customers`

The raw layer was treated as a stable ingestion zone, with no business logic and no premature typing. All cleaning, standardization, 
null handling, and type conversion were deferred to the staging layer.

## Validation
This approach succeeded in creating stable raw landing tables for the available Shopify exports.

Key outcomes included:
- `raw.shopify_orders` loaded successfully from two Shopify CSV exports
- all source values were preserved without type-related ingestion failures
- the raw layer provided a reliable starting point for profiling and staged transformation
- later staging work confirmed that postponing typing was the correct choice given the source inconsistency

## Business impact
This ingestion strategy reduced the risk of breaking the pipeline on messy source data and created a dependable foundation for the warehouse. 
That matters for Mischief Made because the business needs analytics built on complete source capture, not fragile imports that fail when exports are inconsistent.

## Portfolio significance
This milestone demonstrates an important real-world analytics engineering principle: raw ingestion should optimize for source fidelity and pipeline stability, 
not early perfection. Loading messy operational extracts as strings first is a practical and defensible design choice in modern warehouse workflows, 
especially when working with CSV exports from ecommerce platforms.
