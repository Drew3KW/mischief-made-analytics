# 38 - Shopify API Shadow Staging Comparison

## Summary

This milestone created API-derived shadow staging tables in `raw_load` and compared them against the current CSV-derived staging tables.

The goal was to test whether Shopify API-derived raw candidates can support the existing staging contracts before any canonical raw replacement is considered.

## What changed

Added shadow staging build SQL:

```text
sql/staging/create_stg_shopify_products_api_shadow.sql
sql/staging/create_stg_shopify_customers_api_shadow.sql
sql/staging/create_stg_shopify_order_items_api_shadow.sql
sql/staging/create_stg_shopify_orders_api_shadow.sql
```

Added validation SQL:

```text
sql/validation/shopify_api_shadow_staging_comparison.sql
```

Created shadow staging tables:

```text
raw_load.stg_shopify_products_api_shadow
raw_load.stg_shopify_customers_api_shadow
raw_load.stg_shopify_order_items_api_shadow
raw_load.stg_shopify_orders_api_shadow
```

## Design

The shadow staging tables apply the existing staging conventions to API-derived raw candidate tables.

Current production path:

```text
raw.shopify_*
-> staging.stg_shopify_*
-> marts / analysis
```

Shadow comparison path:

```text
raw_load.shopify_*_api_raw_candidate
-> raw_load.stg_shopify_*_api_shadow
-> validation comparison against staging.stg_shopify_*
```

The shadow tables remain isolated in `raw_load`.

## Non-goals

This milestone did not:

- Replace `raw.shopify_products`
- Replace `raw.shopify_customers`
- Replace `raw.shopify_orders`
- Modify production staging models
- Modify marts models
- Modify business-facing analysis models
- Add DAG behavior
- Remove the CSV fallback path

## Validation

The validation query completed successfully.

No checks returned:

```text
FAIL
```

Structural checks passed, including:

- Product shadow rows are present
- Product blank SKUs are filtered
- Product shadow SKUs all exist in current staging
- Customer shadow rows are present
- Customer duplicate customer IDs are zero
- Customer tax-exempt differences are zero
- Order-item shadow rows are present
- Order-item order numbers are complete
- Order-item created timestamps parse successfully
- Order shadow rows are present
- Order duplicate order numbers are zero
- Order line-item counts match on overlap
- Order total item counts match on overlap
- Product compare-at prices match on overlap

Review rows surfaced expected source/snapshot differences:

```text
customer_total_orders_differences_on_overlap: 72
customer_total_spent_differences_on_overlap: 156
order_financial_status_differences_on_overlap: 23
order_total_differences_on_overlap: 2
product_price_differences_on_overlap: 12
```

Informational rows included expected coverage differences:

```text
customer_current_ids_missing_from_shadow: 1
customer_shadow_ids_missing_from_current_staging: 79
customer_shadow_missing_emails: 816
order_current_orders_missing_from_shadow: 23242
order_fulfillment_status_differences_on_overlap: 75
order_shadow_orders_missing_from_current_staging: 48
product_shadow_duplicate_sku_keys: 6
```

## Result

Milestone 38 confirms that API-derived shadow staging is structurally compatible with the existing CSV-derived staging contracts.

The remaining `REVIEW` rows are not blockers. They represent expected differences between current Shopify API state and older CSV-derived warehouse snapshots, including customer lifetime totals, product prices, order statuses, and a small number of order total differences.

## Updated migration path

```text
Shopify API
-> isolated API landing tables
-> API-vs-CSV reconciliation
-> scheduled API landing
-> shadow raw candidates
-> shadow staging comparison
-> eventual canonical raw rebuild
```

## Next step

Next milestone:

```text
39 - Shopify API Canonical Raw Rebuild Design
```

Goal:

```text
Design the first safe canonical raw rebuild strategy using CSV history before a cutover date and API-derived data after the cutover date, without changing production staging or marts yet.
```
