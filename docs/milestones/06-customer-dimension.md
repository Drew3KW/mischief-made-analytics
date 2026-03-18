# Milestone: Build Customer Dimension

## Summary
This milestone created `marts.dim_customers`, a customer dimension built from the Shopify customer export and enriched with order-history rollups.

## Problem
Customer analysis needed a practical business key, but Shopify data included null or blank emails and some mismatch between customer export data and order history.

## Investigation
Profiling showed that nonblank emails were unique in the customer export, making `customer_email` the best practical customer key. 
It also showed that some orders had null emails and that a small number of non-null order emails would not match the customer dimension.

## Decision
`marts.dim_customers` was built at one row per nonblank `customer_email`, combining customer attributes with first-order, last-order, and lifetime order metrics from order history.

## Validation
Validation confirmed one row per nonblank email, no duplicate emails, and only a small number of expected unmatched fact rows.

## Business impact
This created a reliable foundation for repeat-customer analysis, lifetime value analysis, and customer segmentation.

## Portfolio significance
This milestone shows pragmatic key selection and dimensional modeling based on real source behavior rather than idealized assumptions.
