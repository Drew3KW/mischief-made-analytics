# Shopify API Canonical Raw Rebuild Plan

## Purpose

This spike defines a safe future path from reconciled Shopify Admin API landing tables toward canonical raw rebuild logic.

The goal is not to replace the current CSV-derived warehouse yet. The goal is to document the raw table contracts, shadow rebuild strategy, cutover strategy, rollback path, and validation gates required before any production-facing raw replacement.

## Current state

The project currently has two Shopify ingestion paths:

1. CSV ingestion
   - Known-good fallback path
   - Loads Shopify CSV exports into `raw_load`
   - Rebuilds canonical `raw.shopify_*` tables
   - Refreshes staging, marts, analysis, and validation

2. Shopify API landing
   - Scheduled local landing path
   - Lands isolated API data into `raw_load`
   - Reconciled against the CSV-derived warehouse
   - Does not currently modify canonical raw, staging, marts, or analysis

Current API landing tables:

```text
raw_load.shopify_products_api_latest
raw_load.shopify_product_variants_api_latest
raw_load.shopify_customers_api_latest
raw_load.shopify_orders_api_latest
raw_load.shopify_order_line_items_api_latest
```

Current migration path:

```text
Shopify API -> isolated API landing tables -> API-vs-CSV reconciliation -> scheduled API landing -> eventual canonical raw rebuild
```

## Non-goals

This spike does not:

- Replace `raw.shopify_products`
- Replace `raw.shopify_customers`
- Replace `raw.shopify_orders`
- Modify staging models
- Modify marts models
- Modify business-facing analysis models
- Remove the CSV ingestion fallback
- Require full historical API order access
- Require cloud scheduling

## Recommended approach

Use CSV-compatible shadow raw candidate tables in `raw_load` before touching canonical raw.

Recommended future candidate tables:

```text
raw_load.shopify_products_api_raw_candidate
raw_load.shopify_customers_api_raw_candidate
raw_load.shopify_orders_api_raw_candidate
```

These tables should be treated as contract-test outputs, not production source tables.

This approach keeps the current warehouse safe while allowing API-derived data to be shaped, compared, and validated against the existing staging contracts.

## Why `raw_load` first

`raw_load` is already the project layer for temporary source-file and API landing data.

Using `raw_load` for shadow raw candidates keeps the API rebuild experiment close to the current ingestion layer without creating a new production-like dataset too early.

A separate `raw_api` dataset may be useful later if API-derived raw becomes a long-lived parallel source layer, but it is not necessary for the first shadow rebuild design.

## Raw contract principle

The API-derived raw candidates should prioritize staging compatibility over perfect CSV reproduction.

The key question is:

```text
Can this candidate table safely feed the current staging SQL without changing downstream business logic?
```

A field does not need to be identical to the Shopify CSV export if:

- The staging model does not use it
- The downstream warehouse does not depend on it
- The difference is documented
- Validation confirms no business-facing metric drift

## Product raw contract

Current staging dependency:

```text
staging.stg_shopify_products reads from raw.shopify_products
```

Important raw fields used by staging include:

```text
handle
title
body_html
vendor
product_category
type
tags
published
option1_name
option1_value
option2_name
option2_value
option3_name
option3_value
variant_sku
variant_price
variant_compare_at_price
variant_inventory_qty
variant_grams
variant_inventory_tracker
variant_inventory_policy
variant_fulfillment_service
variant_requires_shipping
variant_taxable
image_src
image_position
image_alt_text
variant_barcode
variant_image
variant_weight_unit
cost_per_item
status
```

Likely API mapping strategy:

- Product-level fields come from `raw_load.shopify_products_api_latest`
- Variant-level fields come from `raw_load.shopify_product_variants_api_latest`
- Output grain should remain one row per product variant/SKU candidate
- Blank SKUs can exist in the raw candidate, but staging should continue filtering blank SKUs

Known issues to preserve or document:

- API includes variants missing SKUs
- Prior reconciliation found missing SKU variants are concentrated in non-core products
- Price differences were small and reviewable
- Image/export fields may not reproduce CSV shape exactly

## Customer raw contract

Current staging dependency:

```text
staging.stg_shopify_customers reads from raw.shopify_customers
```

Important raw fields used by staging include:

```text
customer_id
email
first_name
last_name
accepts_email_marketing
accepts_sms_marketing
default_address_company
default_address_address1
default_address_address2
default_address_city
default_address_province_code
default_address_country_code
default_address_zip
default_address_phone
phone
total_spent
total_orders
note
tax_exempt
tags
```

Likely API mapping strategy:

- Use `legacy_resource_id` as `customer_id`
- Normalize API marketing fields into CSV-compatible fields where possible
- Map `number_of_orders` to `total_orders`
- Map `amount_spent` to `total_spent`
- Map default address fields directly where available
- Convert boolean tax-exempt values carefully

Known issues to preserve or document:

- Some API customers have missing emails
- API and CSV total spend/order counts can differ
- Tax-exempt values use different representations between API and CSV
- API tags may be JSON-shaped while CSV tags are string-shaped

## Order raw contract

Current staging dependencies:

```text
staging.stg_shopify_order_items reads from raw.shopify_orders
staging.stg_shopify_orders is built from staged order-item data
```

Important raw fields used by order-item staging include:

```text
Id
Name
Lineitem sku
Lineitem name
Email
Created at
Paid at
Fulfilled at
Cancelled at
Financial Status
Fulfillment Status
Lineitem fulfillment status
Currency
Source
Risk Level
Lineitem quantity
Lineitem price
Lineitem compare at price
Lineitem discount
Subtotal
Shipping
Taxes
Total
Discount Amount
Refunded Amount
Vendor
Billing City
Billing Province
Billing Country
Shipping City
Shipping Province
Shipping Country
Payment Method
Shipping Method
Tags
```

Likely API mapping strategy:

- Order-level fields come from `raw_load.shopify_orders_api_latest`
- Line-item fields come from `raw_load.shopify_order_line_items_api_latest`
- Output grain should remain one row per order line item
- Order-level fields will repeat across line items, matching the CSV-derived raw shape
- `legacy_resource_id` should map to `Id`
- `order_number` should map to `Name`
- API-created timestamps need formatting compatible with current staging parse logic, or staging must eventually be updated in a controlled later milestone

Known issues to preserve or document:

- API order access may only cover a recent window
- Full historical API order access is not required for forward ingestion
- CSV history remains the historical baseline
- API-only orders after the latest CSV staging date are expected
- Fulfillment status can differ between API and CSV
- Payment methods and tags may not exactly match CSV string formatting

## Historical baseline and forward ingestion

Recommended strategy:

```text
CSV-derived canonical raw = historical baseline
API-derived landing = forward scheduled ingestion
cutover date = first date where API landing is trusted as the forward source
```

The cutover date should be chosen only after repeated scheduled API landing runs validate cleanly.

A future canonical rebuild should combine:

1. CSV-derived historical rows before the cutover date
2. API-derived rows on or after the cutover date
3. Deterministic deduplication rules
4. Validation against staging, marts, and dashboard-ready summaries

## Cutover date strategy

The cutover date should be explicit and documented.

Recommended rules:

- Choose a date after API scheduled landing has been stable for multiple runs
- Avoid choosing a date inside a known partial landing window
- Preserve all CSV-derived history before the cutover date
- Treat API-only newer records as expected after cutover
- Do not use the cutover to rewrite old business history unless a separate backfill plan is approved

Candidate pattern:

```text
orders:
  CSV history before cutover date
  API rows on or after cutover date

customers:
  API can eventually become the current-state source after reconciliation gates pass

products:
  API can eventually become the current-state source after reconciliation gates pass
```

## Rollback strategy

Rollback should be simple.

Before production replacement:

- Keep current CSV ingestion DAG intact
- Keep current raw rebuild SQL intact
- Do not delete existing raw tables
- Do not modify staging contracts in the same milestone as raw replacement
- Preserve the ability to rerun CSV ingestion and rebuild canonical raw from CSV files

If API-derived canonical raw replacement fails later:

```text
disable API raw rebuild path
rerun CSV raw load and refresh DAG
restore canonical raw from CSV-derived rebuild logic
rerun warehouse validation
```

## Validation gates before canonical raw replacement

Minimum validation gates:

### Products

- Candidate row count reviewed
- Duplicate variant/SKU behavior reviewed
- Blank SKU count reviewed
- API-only nonblank SKU count equals zero or is explained
- Price differences reviewed
- Downstream `dim_products` row count remains stable
- Non-core product filtering still behaves as expected

### Customers

- Candidate row count reviewed
- Duplicate legacy customer IDs equals zero
- Duplicate normalized nonblank emails reviewed
- Missing email count reviewed
- API-only and staging-only customers reviewed
- Total order count differences reviewed
- Total spent differences reviewed
- Tax-exempt normalization validated
- Downstream `dim_customers` row count remains stable

### Orders

- Candidate order count reviewed
- Candidate line-item count reviewed
- Duplicate order/line-item fingerprints reviewed
- API-only orders after cutover are expected
- Staging-only orders in API window are reviewed
- Order total differences reviewed
- Line-item count differences reviewed
- Total item quantity differences reviewed
- Financial status differences reviewed
- Fulfillment status differences reviewed
- Downstream `fct_orders` and `fct_order_items` remain stable for pre-cutover history

### Warehouse-wide

- Staging refresh succeeds
- Marts refresh succeeds
- Machine-readable validation succeeds
- Dashboard-ready daily/monthly summaries remain explainable
- No unexpected historical metric drift
- CSV fallback remains runnable

