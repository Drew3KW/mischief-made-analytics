# 30 - Shopify API vs CSV Product Reconciliation

## Summary

This milestone added the first reconciliation layer comparing Shopify Admin API product/variant landing data against the existing CSV-derived product warehouse.

The goal was to determine how closely the new API product and variant landing tables match the current CSV-derived product data before making any changes to canonical `raw.shopify_*` tables or downstream business-facing models.

The milestone succeeded.

## What changed

Added an analysis view:

```text
sql/analysis/shopify_api_csv_product_reconciliation.sql
```

This creates:

```text
marts.anl_shopify_api_csv_product_reconciliation
```

The view compares Shopify API product variant records against:

```text
raw_load.shopify_products_api_latest
raw_load.shopify_product_variants_api_latest
raw.shopify_products
staging.stg_shopify_products
marts.dim_products
```

Added a validation query:

```text
sql/validation/shopify_api_csv_product_reconciliation_validation.sql
```

This query validates:

- reconciliation row count
- duplicate API variant GraphQL IDs
- API variants missing SKUs
- API-only variants not found in CSV-derived product data
- API variants matched across CSV raw, staging, and `dim_products`
- price differences between API and staging
- inventory differences between API and staging

## Validation results

The reconciliation view returned one row per API product variant.

Key results:

```text
reconciliation_view_row_count       2436  PASS
duplicate_api_variant_graphql_ids   0     PASS
api_only_variant_rows               0     PASS
matched_api_csv_staging_dim_rows    2209  INFO
api_variants_missing_sku            227   REVIEW
price_differs_from_staging_rows     7     REVIEW
inventory_differs_from_staging_rows 342   INFO
```

Interpretation:

```text
API variants loaded:                         2,436
Matched API -> CSV raw -> staging -> dim:    2,209
API-only nonblank SKU variants:              0
Duplicate API variant IDs:                   0
Missing SKU variants:                        227
Price differences:                           7
```

Approximate clean match rate:

```text
2,209 / 2,436 = 90.7%
```

## Review findings

The 227 API variants missing SKUs were reviewed and found to be concentrated in non-core products such as:

- socks
- pins
- wristlets
- gift cards
- mystery boxes
- accessories

These missing-SKU variants do not appear to block API product/variant landing progress, but they should remain visible before any future canonical raw rebuild.

The 7 price differences were reviewed and all belonged to variants of the same product. This does not appear to indicate a structural reconciliation problem.

The 342 inventory differences are informational because inventory can change frequently and the API pull and CSV export may not represent the same point in time.

## Design decisions

This milestone is comparison-only.

It intentionally does not:

- replace Shopify CSV ingestion
- modify canonical `raw.shopify_*` tables
- modify staging models
- modify marts models other than adding the reconciliation analysis view
- modify downstream business-facing analysis logic
- schedule API ingestion
- use API data as the warehouse source of truth

The CSV ingestion path remains the known-good fallback.

Current migration path:

```text
Shopify API -> isolated API landing tables -> API-vs-CSV comparison layer -> eventual canonical raw rebuild
```

## Result

The project now has a working reconciliation layer proving that Shopify API product and variant data is largely compatible with the existing CSV-derived warehouse shape.

The most important finding is that all API variants with nonblank SKUs were found in the CSV-derived warehouse.

This supports continuing toward API-based product ingestion while keeping the existing CSV path intact.

## Next step

Recommended next milestone:

```text
31 - Shopify API Product Rebuild Planning
```

Suggested goal:

```text
Design a safe future path from API landing and reconciliation tables toward canonical raw product rebuild logic, without changing the current production-facing CSV-derived warehouse yet.
```
