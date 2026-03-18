# Milestone: Build Order-Level Fact Table

## Summary
This milestone created `marts.fct_orders`, the order-level fact table for KPIs such as revenue, average order value, discounts, refunds, and customer order behavior.

## Problem
Although `staging.stg_shopify_orders` already represented order grain well, a mart-layer fact table was needed to formalize order-level metrics in the dimensional model.

## Investigation
The staged order model had already resolved the main grain issue by using `order_number` as the practical business-facing order key and rolling up order-level fields cleanly.

## Decision
`marts.fct_orders` was built from `staging.stg_shopify_orders` as a one-row-per-order fact table with normalized customer email and core order-level measures.

## Validation
Validation confirmed that row count matched staging and that uniqueness checks passed at the order level.

## Business impact
This created the main fact table for order-level KPI analysis and provides the base for AOV, refunds, and customer order reporting.

## Portfolio significance
This milestone shows the promotion of a validated staged model into a clean mart-layer fact designed for business-facing analysis.
