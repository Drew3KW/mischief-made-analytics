# 43 - Automated Shopify Refresh Operations and Runbook

## Summary

This milestone hardened the automated Shopify API canonical refresh flow with a freshness validation gate and an operations runbook.

The goal was to make the automated refresh easier to operate, inspect, and recover from before expanding the project to Etsy integration.

## What changed

Added API landing freshness validation:

```text
sql/validation/shopify_api_landing_freshness_validation.sql
```

Added an operations runbook:

```text
docs/operations/shopify_api_canonical_refresh_runbook.md
```

Updated the master DAG:

```text
dags/mm_shopify_api_canonical_refresh_mvp.py
```

## Freshness validation

The new freshness validation checks that Shopify API landing tables:

```text
contain rows
have api_extracted_at timestamps
were refreshed recently
```

Validated landing tables:

```text
raw_load.shopify_orders_api_latest
raw_load.shopify_order_line_items_api_latest
raw_load.shopify_customers_api_latest
raw_load.shopify_products_api_latest
raw_load.shopify_product_variants_api_latest
```

## Updated automated flow

The master DAG now runs:

```text
Shopify API landing
-> API landing freshness validation
-> API raw candidates
-> API raw candidate validation
-> hybrid raw candidates
-> hybrid raw candidate validation
-> latest canonical raw backup
-> canonical raw replacement
-> warehouse refresh
-> canonical raw replacement validation
```

## Operations runbook

The runbook documents:

```text
normal refresh flow
scheduling model
manual run steps
freshness checks
validation gates
backup tables
rollback steps
failure handling
local-runtime limitations
```

## Non-goals

This milestone did not:

```text
move Airflow to the cloud
add Etsy, Faire, or ads data
modify staging models
modify marts models
modify analysis models
build dashboards
remove the CSV fallback path
```

## Result

Milestone 43 made the automated Shopify refresh more operationally clear and safer to manage.

The project now has a documented refresh flow, a freshness validation gate, and clear rollback guidance before beginning Etsy integration.

## Next step


```text
44 - Etsy Source Integration Spike
```

Goal:

```text
Explore Etsy data access, authentication, order/transaction endpoints or exports, and field mapping needed for future cross-channel revenue modeling.
```
