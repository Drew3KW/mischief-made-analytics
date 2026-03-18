# Milestone: Build Line-Item Staging Model

## Summary
This milestone created `staging.stg_shopify_order_items`, the cleaned and typed staging model for Shopify order line items.

## Problem
The raw Shopify orders export was messy and not analytics-ready. It contained inconsistent null handling, repeated order-level fields, and mixed data quality across rows.

## Investigation
Profiling showed that:
- the export was truly at line-item grain
- some orders contained the same SKU on multiple rows
- order-level fields were repeated across line items
- numeric and timestamp fields needed careful cleaning and typing

## Decision
`staging.stg_shopify_order_items` was built as a one-row-per-line-item model with cleaned fields, typed values, normalized keys, and preserved source detail.

## Validation
Validation confirmed that the model retained the full source row count and correctly represented line-item grain.

## Business impact
This created the foundation for product-level sales analysis and downstream fact modeling.

## Portfolio significance
This milestone shows careful source profiling, grain validation, and disciplined staging design on messy ecommerce exports.
