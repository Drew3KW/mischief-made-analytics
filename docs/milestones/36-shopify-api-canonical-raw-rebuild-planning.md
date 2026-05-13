# 36 - Shopify API Canonical Raw Rebuild Planning

## Summary

This milestone planned a safe future path from reconciled Shopify Admin API landing data toward canonical raw rebuild logic.

The milestone intentionally did not replace canonical raw tables or modify staging, marts, or business-facing analysis. The CSV ingestion path remains the known-good fallback.

## What changed

Added planning documentation:

```text
docs/spikes/shopify-api-canonical-raw-rebuild-plan.md
```

The planning document covers:

- API-derived raw table contracts
- Staging compatibility requirements
- Product, customer, and order raw candidate strategy
- Historical CSV baseline strategy
- Forward API ingestion strategy
- Cutover date strategy
- Rollback strategy
- Validation gates required before canonical raw replacement

## Design decision

The recommended first step is to create CSV-compatible shadow raw candidate tables in `raw_load`, not to replace canonical `raw.shopify_*` tables.

Recommended future candidate tables:

```text
raw_load.shopify_products_api_raw_candidate
raw_load.shopify_customers_api_raw_candidate
raw_load.shopify_orders_api_raw_candidate
```

These should be used for contract testing and validation only.

## Non-goals

This milestone did not:

- Replace `raw.shopify_products`
- Replace `raw.shopify_customers`
- Replace `raw.shopify_orders`
- Modify staging models
- Modify marts models
- Modify business-facing analysis models
- Remove the CSV fallback path
- Add new DAG behavior
- Add new production SQL behavior

## Current migration path

The project remains on the safe migration path:

```text
Shopify API -> isolated API landing tables -> API-vs-CSV reconciliation -> scheduled API landing -> shadow raw candidates -> eventual canonical raw rebuild
```

## Result

The project now has a documented plan for moving from scheduled Shopify API landing toward canonical raw rebuild logic.

The plan preserves the current working CSV-derived warehouse while defining the next safe implementation step: API-derived shadow raw candidate tables.

## Next step

Next milestone:

```text
37 - Shopify API Shadow Raw Candidate Tables
```

Goal:

```text
Create API-derived raw candidate tables in raw_load and validate them against current CSV-derived raw/staging contracts without changing production-facing warehouse models.
```
