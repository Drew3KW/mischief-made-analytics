# Milestone 45 - Etsy Orders Landing MVP

## Goal

Build the first isolated Etsy orders landing path for Mischief Made Analytics.

This milestone moves Etsy from source-system spike to working BigQuery landing tables while keeping Etsy data separate from production Shopify raw tables, staging models, marts, analysis queries, and the automated Shopify refresh flow.

## Why this matters

Etsy is a major Mischief Made sales channel. The warehouse needs Etsy order data before the project can support reliable cross-channel revenue analysis or a business-facing dashboard.

Milestone 45 establishes the first repeatable Etsy ingestion path and validates that receipts, receipt transactions, and receipt payments can be landed safely in BigQuery.

## Scope

Completed:

- Added a local Etsy orders landing script:
  - `scripts/etsy_orders_landing.py`
- Loaded Etsy receipt/order-header data into BigQuery:
  - `raw_load.etsy_receipts_api_latest`
- Loaded Etsy receipt transaction/order-item data into BigQuery:
  - `raw_load.etsy_receipt_transactions_api_latest`
- Loaded Etsy receipt payment data into BigQuery:
  - `raw_load.etsy_receipt_payments_api_latest`
- Added landing-level validation SQL:
  - `sql/validation/etsy_orders_landing_validation.sql`
- Validated row counts, key uniqueness, null required IDs, parent receipt relationships, and known edge cases.
- Preserved the existing Shopify automated refresh flow unchanged.
- Kept Etsy landing isolated in `raw_load`.

## Non-goals

Not included:

- No production `raw` table changes.
- No staging, marts, or analysis models for Etsy yet.
- No cross-channel revenue model yet.
- No Etsy Airflow orchestration yet.
- No changes to the Shopify automated refresh flow.
- No committed Etsy credentials, tokens, or local API output.
- No final Etsy net revenue definition yet.

## Files added or updated

Added:

- `scripts/etsy_orders_landing.py`
- `sql/validation/etsy_orders_landing_validation.sql`
- `docs/milestones/milestone-45-etsy-orders-landing-mvp.md`

Updated:

- `README.md`

Local-only files used but not committed:

- `.env`
- `local_data/etsy_api_spike/oauth_token.json`
- `keys/gcp-sa.json`

## Landing flow

The local landing script performs this flow:

```text
Etsy Open API
-> refresh OAuth access token
-> fetch recent receipts
-> flatten receipt/order-header records
-> flatten nested receipt transaction/order-item records
-> fetch receipt payment records where available
-> replace raw_load Etsy landing tables
```

The default execution pattern is:

```bash
python scripts/etsy_orders_landing.py --days 30
```

## Landing tables

### `raw_load.etsy_receipts_api_latest`

Grain:

- One row per Etsy receipt.

Purpose:

- Order-header landing table.

Important fields include:

- `receipt_id`
- `receipt_type`
- `status`
- `is_paid`
- `is_shipped`
- `buyer_user_id`
- `buyer_email`
- `seller_user_id`
- order timestamps
- customer and shipping address fields
- discount amount
- subtotal
- grand total
- total price
- shipping cost
- tax cost
- VAT cost
- gift wrap price
- refunds JSON
- shipments JSON
- transactions JSON
- raw JSON

### `raw_load.etsy_receipt_transactions_api_latest`

Grain:

- One row per Etsy receipt transaction.

Purpose:

- Order-item landing table.

Important fields include:

- `transaction_id`
- `receipt_id`
- `transaction_type`
- `buyer_user_id`
- `seller_user_id`
- `listing_id`
- `product_id`
- `sku`
- `title`
- `description`
- `quantity`
- item timestamps
- shipping fields
- item price
- shipping cost
- coupon fields
- product data JSON
- variations JSON
- raw JSON

### `raw_load.etsy_receipt_payments_api_latest`

Grain:

- One row per Etsy receipt payment.

Purpose:

- Payment, fee, gross, net, and adjustment landing table.

Important fields include:

- `payment_id`
- `receipt_id`
- `shop_id`
- `buyer_user_id`
- `status`
- currency fields
- payment timestamps
- gross amount
- fee amount
- net amount
- adjusted gross amount
- adjusted fee amount
- adjusted net amount
- posted gross amount
- posted fee amount
- posted net amount
- payment adjustments JSON
- raw JSON

## Validation

Validation file:

```text
sql/validation/etsy_orders_landing_validation.sql
```

Validation covers:

- receipt row count
- transaction row count
- payment row count
- duplicate `receipt_id` values
- duplicate `transaction_id` values
- duplicate `payment_id` values
- null required IDs
- transaction-to-receipt parent relationships
- payment-to-receipt parent relationships
- receipts without transactions
- receipts without payments
- blank SKUs
- null quantity
- null price
- null payment gross, fee, and net values
- receipt timestamp range
- landing row summary

## Validation result

The validation completed with no blocking failures.

Result summary:

```text
PASS: 19
REVIEW: 2
INFO: 2
FAIL: 0
```

Landing row summary:

```text
receipts=173, transactions=254, payments=169
```

Timestamp range:

```text
2026-04-19 00:37:52+00 to 2026-05-18 22:10:14+00
```

Review items:

```text
etsy_receipts_missing_payments = 4
etsy_transactions_blank_sku = 1
```

The 4 missing payment rows match Etsy receipt-payment endpoint 404 behavior observed during extraction. These records remain landed at receipt and transaction grain.

The 1 blank SKU affects future product mapping but does not block landing.

## Implementation notes

The landing script refreshes the Etsy OAuth access token before extraction.

Receipt payments are fetched per receipt. Etsy returned 404 responses for 4 receipt payment fetches in the validated run. The script treats these as non-blocking skipped payment fetches and continues the landing.

Etsy money objects are converted into numeric amount fields and companion currency fields. Nested or variable-shape fields are preserved as JSON strings so that raw source context remains available for later modeling.

Each landing run replaces the `_latest` tables. This keeps the Milestone 45 implementation simple and makes the current landing state easy to validate.

## Outcome

Milestone 45 successfully established the first working Etsy landing path in BigQuery.

The project now has isolated Etsy landing tables for:

- receipts
- receipt transactions
- receipt payments

These tables provide the foundation for Etsy staging models, Etsy order marts, and cross-channel Shopify plus Etsy revenue modeling.

## Next milestone

Milestone 46 - Cross-Channel Revenue Model MVP

Planned focus:

- Create the first combined Shopify plus Etsy order/revenue model.
- Preserve channel-specific source details.
- Define channel-aware order keys.
- Handle Etsy missing payment edge cases explicitly.
- Avoid finalizing customer identity matching until customer modeling is handled deliberately.
- Build validation that compares source landing counts to the first cross-channel model.
