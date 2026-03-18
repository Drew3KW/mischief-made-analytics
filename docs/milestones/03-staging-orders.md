# Milestone: Build Order-Grain Staging Model

## Summary
This milestone created `staging.stg_shopify_orders`, a one-row-per-order staging model built from Shopify’s line-item-grain orders export.

## Problem
The raw Shopify orders export was not actually at order grain. Order-level fields were repeated across line items, 
and an early grouping approach using both `shopify_order_id` and `order_number` fragmented orders incorrectly.

## Investigation
Profiling showed that:
- the source export was line-item grain
- `order_number` was the most reliable business-facing order key
- grouping by both `shopify_order_id` and `order_number` split some orders into multiple rows
- `shopify_order_id` could still be retained using `MAX()`

## Decision
`staging.stg_shopify_orders` was built by grouping to one row per `order_number`, while recovering `shopify_order_id` with `MAX()` and 
rolling up order-level attributes into a clean order-grain model.

## Validation
Validation confirmed:
- one row per order
- row counts aligned with distinct order numbers
- the fragmentation issue was resolved

## Business impact
This created a reliable order-level foundation for KPIs such as revenue, AOV, refunds, and customer order behavior.

## Portfolio significance
This milestone demonstrates careful grain validation and a real-world modeling decision driven by source behavior rather than assumptions.
