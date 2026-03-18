# Milestone: Build Current Product Dimension

## Summary
This milestone created `marts.dim_products`, a current-catalog product dimension built from the Shopify product export at one row per SKU.

## Problem
The raw product export contained duplicate SKUs and inconsistent record quality, so it could not be used directly as a clean product dimension.

## Investigation
Profiling showed that some duplicate SKUs were real catalog issues rather than harmless duplicates. In several cases, the same SKU appeared across multiple rows with different completeness or status.

## Decision
`marts.dim_products` was built with one row per SKU using deduplication rules that preferred active products and more complete attributes.

## Validation
Validation confirmed that row count matched distinct SKU count and that duplicate SKU checks returned zero rows.

## Business impact
This created a usable current-catalog dimension for product attributes and current assortment analysis.

## Portfolio significance
This milestone shows practical dimensional modeling and the use of source profiling to resolve real catalog quality issues.
