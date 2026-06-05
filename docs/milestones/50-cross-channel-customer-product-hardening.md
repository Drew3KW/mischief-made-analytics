# Milestone 50 - Cross-Channel Customer and Product Hardening

## Summary

Milestone 50 adds a conservative cross-channel customer and product hardening layer for the Mischief Made analytics warehouse.

This milestone does not force full identity resolution. Instead, it creates explicit bridge models, cross-channel dimensions, audit views, and validation so Shopify and Etsy customer/product semantics can be compared safely and extended later.

## Goals

- Audit Shopify and Etsy customer overlap.
- Audit Etsy listing/SKU/title patterns against Shopify product families.
- Create explicit cross-channel bridge tables.
- Create conservative cross-channel customer and product-family dimensions.
- Keep unresolved and review-only cases visible.
- Add validation for bridge uniqueness, expected statuses, source row-count tieouts, and known Etsy source behavior.
- Wire the new models and validations into the active Airflow DAGs.

## Added Models

### Analysis / Audit Views

- `sql/analysis/cross_channel_customer_overlap_audit.sql`
- `sql/analysis/cross_channel_product_family_mapping_audit.sql`

### Bridge Models

- `sql/marts/cross_channel_customer_bridge.sql`
- `sql/marts/cross_channel_product_family_bridge.sql`

### Cross-Channel Dimensions

- `sql/marts/dim_cross_channel_customers.sql`
- `sql/marts/dim_cross_channel_product_families.sql`

### Validation

- `sql/validation/cross_channel_identity_hardening_validation.sql`

## Customer Identity Findings

The customer audit confirmed that Etsy buyer email is not currently available in the modeled Etsy API data.

Observed raw Etsy receipt behavior:

- `buyer_email` exists as a JSON key.
- `buyer_email` is returned as `null` for all current receipt rows.
- `seller_email` is populated, confirming that email extraction itself is working.

Because Etsy buyer email is unavailable, the customer bridge intentionally keeps:

- Shopify customers as `channel_only`
- Etsy buyers as `unresolved`

The model supports future `exact_email` matching if Etsy buyer email becomes available later.

## Product-Family Findings

The product-family audit found strong SKU-based coverage between Etsy listings and Shopify product families.

Accepted automated product-family matches use:

- `exact_sku`
- `sku_family`

Title-pattern matches remain visible as `review_candidate` rows rather than being automatically accepted.

Unresolved Etsy listings remain visible as `unresolved`.

## Final Customer Dimension Shape

The final customer dimension is conservative:

- Etsy unresolved customers: 11,763
- Shopify channel-only customers: 20,972

No cross-channel customer merges are forced.

## Final Product-Family Dimension Shape

The final product-family dimension includes:

- Cross-channel accepted product-family rows
- Shopify-only product-family rows
- Etsy review-candidate rows
- Etsy unresolved rows

Accepted Etsy listing matches are rolled up into Shopify product-family keys only when the bridge logic supports the match.

## Airflow Updates

Updated DAGs:

- `dags/mm_bigquery_refresh_mvp.py`
- `dags/mm_etsy_recent_refresh_mvp.py`

The main BigQuery refresh DAG now rebuilds:

- source-native staging and marts
- cross-channel customer/product bridge tables
- cross-channel customer/product dimensions
- audit views
- cross-channel identity hardening validation

The Etsy recent refresh DAG now rebuilds and validates the cross-channel hardening layer after Etsy-native dimensions refresh and before cross-channel revenue/dashboard outputs.

## Validation

Validation checks include:

- customer bridge source grain uniqueness
- product bridge source grain uniqueness
- expected customer match types
- expected product match types
- expected bridge resolution statuses
- accepted Etsy product rows have mapped product-family keys
- customer bridge row counts tie to source dimensions
- product bridge row counts tie to source dimensions
- cross-channel customer dimension key uniqueness
- cross-channel product-family dimension key uniqueness
- dimension row counts match distinct bridge keys
- unresolved Etsy customers remain visible
- Etsy product review candidates remain visible
- unresolved Etsy product rows remain visible
- Etsy buyer email source behavior is documented as an INFO row

Final validation returned no FAIL rows.

## DAG Checks

The following checks passed:

- Python compile check for `mm_bigquery_refresh_mvp.py`
- Python compile check for `mm_etsy_recent_refresh_mvp.py`
- Airflow DAG import check
- Manual Airflow run for `mm_bigquery_refresh_mvp`
- Manual Airflow run for `mm_etsy_recent_refresh_mvp`

## Deferred Work

This milestone intentionally does not implement:

- fuzzy customer matching
- forced customer identity resolution
- manual customer matching
- full Etsy listing catalog ingestion
- payout/accounting reconciliation
- COGS/profit modeling
- ad spend integration
- dashboard migration to the new cross-channel customer/product dimensions

## Outcome

Milestone 50 establishes a safe, explicit, and auditable foundation for cross-channel customer and product semantics.

The warehouse can now represent:

- Shopify-native customer identity
- Etsy-native customer identity
- unresolved Etsy customer identity due to API buyer email limitations
- Shopify-native product families
- accepted Etsy-to-Shopify product-family matches
- review-only Etsy title-pattern candidates
- unresolved Etsy listings

This creates a durable bridge layer for future dashboard, profitability, and identity-resolution work.
