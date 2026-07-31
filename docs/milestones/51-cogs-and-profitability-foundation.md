# Milestone 51: COGS & Profitability Foundation

## Summary

Milestone 51 establishes a conservative cross-channel item-level profitability foundation for Mischief Made.

This milestone adds manual COGS ingestion, COGS matching maps, cross-channel order item profitability modeling, profitability analysis views, and validation coverage. The model intentionally avoids unsafe broad automated cost inference. Instead, it uses a clear matching ladder and exposes COGS coverage so profitability reporting remains transparent.

## Scope

This milestone adds:

* Manual COGS CSV ingestion support
* Manual product-family COGS override ingestion support
* SKU-level COGS mapping
* Product-family COGS fallback mapping
* Product name/type COGS fallback mapping
* Manual product-family override mapping
* Cross-channel order item fact with estimated COGS and gross profit
* Product profitability summary view
* Monthly product profitability view
* Profitability foundation validation
* Airflow DAG integration for the new marts, analysis views, and validation

## Key Models

### Raw load

* `raw_load.product_cogs_manual_latest`
* `raw_load.product_family_cogs_overrides_latest`

### Marts

* `marts.product_cogs_map`
* `marts.product_family_cogs_map`
* `marts.product_name_type_cogs_map`
* `marts.product_family_cogs_override_map`
* `marts.fct_cross_channel_order_items`

### Analysis

* `marts.anl_product_profitability_summary`
* `marts.anl_product_profitability_monthly`

### Validation

* `sql/validation/profitability_foundation_validation.sql`

## COGS Matching Ladder

The cross-channel item fact resolves COGS using a conservative ladder:

1. Exact SKU match
2. Manual product-family override
3. Product-family fallback
4. Product name/type fallback
5. Manual exclusion
6. Missing or review status

Rows without accepted COGS remain visible with diagnostic statuses instead of being silently excluded.

## Profit Metrics

The profitability model includes:

* Unit COGS
* Estimated item COGS
* Estimated gross profit before fees
* Estimated gross margin before fees
* COGS match grain
* COGS resolution status
* Product type group
* Product subtype group
* COGS coverage metrics

Profit is estimated before channel fees, ad spend, shipping, labor, overhead, and payout reconciliation.

## Validation

The validation file checks:

* Raw COGS data is loaded
* COGS maps have unique keys
* Usable COGS rows have unit costs
* Override rows are valid and non-conflicting
* Cross-channel item keys are unique
* Cross-channel item fact row count ties to Shopify and Etsy source item facts
* Accepted COGS rows have cost and profit values
* Profitability views return rows
* Profitability view revenue ties to the cross-channel item fact
* Recent 365-day COGS coverage is materially useful
* All-time COGS coverage is reported informationally

Final DAG run succeeded with no failing validation rows.

## Important Decision

A broader automated COGS inference layer was investigated but not implemented for broad apparel categories. Audit results showed that broad groups such as tees, raglans, cardigans, and sweaters had too many distinct cost values to infer safely.

The milestone therefore prioritizes conservative, auditable profitability modeling over fake precision.

## Operational Notes

The COGS CSV files are local/private inputs and are not committed to Git:

* `local_data/cogs/product_cogs_manual_latest.csv`
* `local_data/cogs/product_family_cogs_overrides_latest.csv`

Current workflow:

1. Export/update the local COGS CSV files.
2. Run the manual loader scripts.
3. Trigger `mm_bigquery_refresh_mvp`.
4. Confirm profitability validation has no `FAIL` rows.

## Result

Milestone 51 provides a credible foundation for product profitability analysis, especially for recent/current business performance, while preserving transparency around historical COGS gaps.
