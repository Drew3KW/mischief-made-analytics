# Milestone 49 - Etsy Staging and Marts MVP

## Summary

Milestone 49 turns Etsy latest landing data into validated Etsy-native staging, fact, and dimension models.

This milestone creates a clean Etsy semantic layer on top of the existing Etsy API landing/backfill pipeline. It does not attempt cross-channel customer identity resolution or Shopify/Etsy product-family harmonization.

## Goal

Build reusable Etsy-native models from the current Etsy latest landing tables:

- `raw_load.etsy_receipts_api_latest`
- `raw_load.etsy_receipt_transactions_api_latest`
- `raw_load.etsy_receipt_payments_api_latest`

The milestone converts these landing tables into:

- cleaned staging models
- Etsy-native fact models
- Etsy-native dimension models
- validation queries
- Airflow orchestration

## Implemented Files

### Staging

- `sql/staging/stg_etsy_receipts.sql`
- `sql/staging/stg_etsy_receipt_transactions.sql`
- `sql/staging/stg_etsy_receipt_payments.sql`

### Marts

- `sql/marts/fct_etsy_orders.sql`
- `sql/marts/fct_etsy_order_items.sql`
- `sql/marts/fct_etsy_payments.sql`
- `sql/marts/dim_etsy_customers.sql`
- `sql/marts/dim_etsy_listings.sql`

### Validation

- `sql/validation/etsy_staging_validation.sql`
- `sql/validation/etsy_marts_validation.sql`
- `sql/validation/etsy_dimensions_validation.sql`

### Orchestration

Updated:

- `dags/mm_bigquery_refresh_mvp.py`
- `dags/mm_etsy_recent_refresh_mvp.py`

## Staging Models

### `staging.stg_etsy_receipts`

Grain:

- one row per Etsy `receipt_id`

Purpose:

- clean and type Etsy receipt/order-header landing data

Key fields:

- `receipt_id`
- `etsy_receipt_key`
- `receipt_status`
- `buyer_user_id`
- `etsy_buyer_key`
- `buyer_email`
- `receipt_created_at`
- `receipt_created_date`
- `receipt_updated_at`
- `receipt_updated_date`
- shipping geography
- receipt/order money fields
- retained JSON payloads

Notes:

- `receipt_id` is the native Etsy order/header key.
- `buyer_user_id` is the practical Etsy-native customer key for now.
- Cross-channel customer identity resolution is deferred.

### `staging.stg_etsy_receipt_transactions`

Grain:

- one row per Etsy `transaction_id`

Purpose:

- clean and type Etsy receipt transaction/order-item landing data

Key fields:

- `transaction_id`
- `etsy_transaction_key`
- `receipt_id`
- `etsy_receipt_key`
- `buyer_user_id`
- `etsy_buyer_key`
- `listing_id`
- `etsy_listing_key`
- `product_id`
- `etsy_product_key`
- `sku`
- `listing_title`
- `quantity`
- `item_price`
- `item_gross_amount`
- transaction, paid, shipped, and expected ship dates
- retained JSON payloads

Notes:

- `transaction_id` is the native Etsy order-item key.
- Some Etsy transaction rows have blank SKUs.
- Product-family harmonization is deferred.

### `staging.stg_etsy_receipt_payments`

Grain:

- one row per Etsy `payment_id`

Purpose:

- clean and type Etsy receipt payment landing data

Key fields:

- `payment_id`
- `etsy_payment_key`
- `receipt_id`
- `etsy_receipt_key`
- `payment_status`
- `currency`
- payment created, updated, and shipped dates
- original payment amount fields
- adjusted payment amount fields
- posted payment amount fields
- selected practical payment amount fields
- retained JSON payloads

Notes:

- Some receipts have no payment row because Etsy returned 404 for the receipt payment endpoint.
- `selected_*` payment fields coalesce adjusted, original, and posted Etsy values.
- Etsy payment net is not treated as full accounting net.

## Mart Models

### `marts.fct_etsy_orders`

Grain:

- one row per Etsy receipt/order

Purpose:

- Etsy-native order fact built from staged receipts, transaction rollups, and payment rollups

Includes:

- channel and order keys
- receipt status
- buyer identifiers
- order dates
- shipping geography
- receipt/order amounts
- order-item rollups
- payment rollups
- practical flags

Important flags:

- `has_payment_record`
- `missing_payment_record`
- `has_blank_sku`
- `has_refunds_json`

### `marts.fct_etsy_order_items`

Grain:

- one row per Etsy receipt transaction

Purpose:

- Etsy-native order-item fact built from staged Etsy receipt transactions

Includes:

- channel and order-item keys
- order context
- transaction dates
- buyer identifiers
- listing and product identifiers
- SKU/title fields
- quantity and item money fields
- blank SKU flag

### `marts.fct_etsy_payments`

Grain:

- one row per Etsy receipt payment

Purpose:

- Etsy-native payment fact built from staged Etsy receipt payments

Includes:

- channel and payment keys
- order context
- buyer and shop identifiers
- payment status/currency
- payment dates
- original amount fields
- adjusted amount fields
- posted amount fields
- selected practical payment fields
- missing receipt and adjusted-net flags

### `marts.dim_etsy_customers`

Grain:

- one row per Etsy `buyer_user_id`

Purpose:

- Etsy-native customer dimension built from Etsy order facts

Includes:

- first and last order dates
- lifetime order count
- lifetime item count
- lifetime gross revenue
- payment fee/net rollups
- payment coverage counts
- latest shipping geography
- Etsy-native customer type
- Etsy-native recency segment

Notes:

- `buyer_user_id` is the practical Etsy-native customer key.
- `buyer_email` may be null in Etsy source data.
- Cross-channel customer identity resolution is deferred.

### `marts.dim_etsy_listings`

Grain:

- one row per Etsy `listing_id`

Purpose:

- Etsy-native listing dimension built from Etsy order-item facts

Includes:

- latest listing title
- latest listing description
- latest SKU
- observed product IDs
- observed SKUs
- lifetime order count
- lifetime order-item count
- lifetime units sold
- lifetime item gross revenue
- first and last sold dates
- blank SKU count
- Etsy-native listing recency segment

Notes:

- `listing_id` is the practical Etsy-native product/listing key for now.
- Cross-channel product-family harmonization is deferred.

## Validation

### `etsy_staging_validation.sql`

Validates:

- staging row counts
- unique staging keys
- null key checks
- date checks
- negative money/count checks
- transaction-to-receipt integrity
- payment-to-receipt integrity
- expected receipt/payment coverage gap

Final result:

- no `FAIL` rows
- payment coverage info row returned `130`, matching known skipped receipt-payment 404s

### `etsy_marts_validation.sql`

Validates:

- mart row counts
- staging-to-mart count alignment
- unique fact keys
- null key checks
- order-item-to-order integrity
- payment-to-order integrity
- order-item rollups against order fact
- payment rollups against order fact
- payment coverage flag alignment

Final result:

- no `FAIL` rows
- payment coverage info row returned `130`
- blank SKU info row returned `820`

### `etsy_dimensions_validation.sql`

Validates:

- dimension row counts
- unique dimension keys
- null key checks
- first/last date checks
- lifetime count and revenue checks
- expected segment values
- fact-to-dimension integrity
- customer rollups against order fact
- listing rollups against order-item fact

Final result:

- no `FAIL` rows

## Airflow Updates

### `mm_bigquery_refresh_mvp`

Updated to rebuild:

- Etsy staging models
- Etsy fact models
- Etsy dimension models
- Etsy validations

The main refresh DAG now includes the Etsy-native model layer as part of the warehouse refresh.

### `mm_etsy_recent_refresh_mvp`

Updated active Etsy recent refresh flow:

Etsy recent API landing
-> recent candidate promotion to latest
-> Etsy landing validation
-> Etsy staging models
-> Etsy staging validation
-> Etsy fact models
-> Etsy mart validation
-> Etsy dimensions
-> Etsy dimension validation
-> cross-channel revenue model rebuild
-> cross-channel analysis/dashboard rebuild
-> final validations

This keeps the active Etsy refresh path validated from landing through Etsy-native marts before downstream cross-channel outputs rebuild.

## Validation Performed

Manual model runs completed successfully for:

- `stg_etsy_receipts`
- `stg_etsy_receipt_transactions`
- `stg_etsy_receipt_payments`
- `fct_etsy_orders`
- `fct_etsy_order_items`
- `fct_etsy_payments`
- `dim_etsy_customers`
- `dim_etsy_listings`

Manual validation completed successfully for:

- `etsy_staging_validation.sql`
- `etsy_marts_validation.sql`
- `etsy_dimensions_validation.sql`

DAG checks:

- `python -m py_compile dags/mm_bigquery_refresh_mvp.py`
- `python -m py_compile dags/mm_etsy_recent_refresh_mvp.py`
- Airflow DAG import check passed after saving all validation files.
- `mm_bigquery_refresh_mvp` ran successfully.
- `mm_etsy_recent_refresh_mvp` ran successfully.

Final result:

- no `FAIL` rows in Etsy staging, marts, or dimension validations

## Known Source Behaviors

### Missing payment rows

There are 130 Etsy receipts without payment rows.

This is expected and traces back to known Etsy receipt-payment endpoint 404 responses handled during historical payment enrichment.

### Blank SKUs

There are 820 Etsy order-item rows with blank SKUs.

This is expected source behavior. Etsy `transaction_id` is the order-item key, so blank SKUs do not block staging or mart modeling.

### Etsy payment net

Etsy payment net is channel-reported payment net, not full accounting net.

It may reflect marketplace/tax/payment behavior beyond visible Etsy fees. Full payout and accounting reconciliation is deferred.

## Deferred

Milestone 49 does not implement:

- cross-channel customer identity resolution
- cross-channel product-family harmonization
- full Etsy listing catalog ingestion
- Etsy ledger/payout reconciliation
- COGS/profit modeling
- ad spend integration
- Faire integration

## Outcome

Milestone 49 establishes a validated Etsy-native semantic layer.

The warehouse now has clean Etsy staging, order facts, order-item facts, payment facts, customer dimensions, and listing dimensions, all wired into the main warehouse refresh and active Etsy recent refresh DAGs.

This prepares the project for Milestone 50: cross-channel customer and product hardening.
