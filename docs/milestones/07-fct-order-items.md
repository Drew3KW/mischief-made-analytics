# Milestone: Build Line-Item Fact Table

## Summary
This milestone created `marts.fct_order_items`, the line-item fact table for product-level sales analysis. 
It was built from `staging.stg_shopify_order_items` and designed to support reliable analysis of units sold, product revenue, discounts, and product mix.

## Problem
The line-item fact needed to support historical product analysis, but the current Shopify product export did not fully cover historically sold items. 
Some sold rows had blank SKUs, and many older products had been deleted from Shopify. 
Repeated order-level monetary fields in the source also made the fact design noisy and potentially misleading.

## Investigation
Profiling showed that:
- the source was truly at line-item grain
- some orders contained the same SKU on multiple rows
- repeated order-level fields were inconsistently populated across line items
- product joins improved dramatically when using `dim_products_historical` instead of the current catalog dimension

## Decision
`marts.fct_order_items` was built at one row per order line item.

Key design choices:
- join products through `product_key` to `dim_products_historical`
- normalize `customer_email` with `LOWER(TRIM(...))`
- remove repeated order-level monetary fields from the fact
- generate a synthetic `order_item_key` for uniqueness

## Validation
Validation confirmed:
- row count matched staging exactly: 47,267
- no duplicate `order_item_key` values
- zero unmatched rows to `dim_products_historical`
- a small number of unmatched customer emails remained, which was expected

## Business impact
This created a reliable foundation for product-level analysis, including revenue by product, 
units sold, discount analysis, and product mix across historical sales.

## Portfolio significance
This milestone shows fact table design grounded in grain discipline, practical dimensional modeling, and real-world source limitations. 
It also demonstrates how historical coverage issues can be solved without losing analytical usefulness.
