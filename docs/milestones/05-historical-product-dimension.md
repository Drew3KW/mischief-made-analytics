# Milestone: Build Historical Product Dimension

## Summary
This milestone solved incomplete historical product coverage in the warehouse by creating a dedicated product dimension that could represent 
both current catalog products and historical sold items no longer present in the Shopify product export.

## Problem
Initial joins between order items and the current product dimension showed poor coverage. Many sold line items did not match a current catalog product.

## Investigation
Profiling showed that the mismatch was caused by several real-world source issues:
- old Mischief Made products had been deleted from Shopify
- many order-item rows had blank SKU values
- some blank-SKU rows represented third-party or non-core items
- some descriptive product names represented historical items no longer in the catalog

This showed that the current Shopify product export could not serve as a complete historical product dimension.

## Decision
A new historical product dimension, `marts.dim_products_historical`, was created.

A unified `product_key` was defined as:
- `SKU|<normalized sku>` when a nonblank SKU exists
- `NAME|<normalized product_name>` otherwise

This allowed the model to unify:
- current catalog products
- deleted historical products
- blank-SKU sold items

`marts.fct_order_items` was then rebuilt to join through `product_key`.

## Validation
Validation confirmed:
- 6,185 total rows
- 6,185 distinct `product_key` values
- zero duplicate `product_key` values
- zero unmatched fact rows when joining `fct_order_items` to `dim_products_historical`

## Business impact
This made historical product sales analysis reliable, even when products had been deleted from Shopify or sold without a usable SKU. That is critical for understanding what has actually sold over time.

## Portfolio significance
This is a strong example of analytics engineering because it shows iterative remodeling driven by source profiling, real business context, and the need to balance technical correctness with business usefulness.
