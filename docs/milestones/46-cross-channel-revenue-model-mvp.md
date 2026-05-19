# Milestone 46 - Cross-Channel Revenue Model MVP

## Goal

Build the first validated cross-channel revenue layer for Mischief Made Analytics by combining mature Shopify order facts with newly landed Etsy order and payment data.

This milestone creates a channel-aware revenue model that supports daily revenue reporting across Shopify and Etsy while deliberately deferring customer identity resolution, product-family harmonization, and full accounting reconciliation.

## Why this matters

Mischief Made sells through both Shopify and Etsy. A Shopify-only revenue view is incomplete once Etsy becomes part of the warehouse.

Milestone 46 creates the first business-facing model that can answer:

```text
How much revenue did Mischief Made generate across Shopify and Etsy, by date and channel?
```

## Scope

Completed:

- Added cross-channel order-level fact table:
  - `sql/marts/fct_cross_channel_orders.sql`
- Added long-format daily cross-channel revenue view:
  - `sql/analysis/cross_channel_revenue_daily.sql`
- Added side-by-side daily Shopify/Etsy revenue pivot:
  - `sql/analysis/cross_channel_revenue_daily_pivot.sql`
- Added cross-channel validation:
  - `sql/validation/cross_channel_revenue_validation.sql`
- Validated source row counts, channel coverage, key uniqueness, required fields, daily rollups, and pivot consistency.
- Preserved the existing Shopify automated refresh flow unchanged.
- Preserved Etsy as landing-driven input data, without promoting Etsy into production raw/staging models yet.

## Non-goals

Not included:

- No full Etsy production integration.
- No Etsy staging models yet.
- No Etsy product or listing catalog model.
- No cross-channel customer identity resolution.
- No product-family harmonization across Shopify and Etsy.
- No full Etsy accounting or payout reconciliation.
- No Etsy Airflow orchestration.
- No changes to the Shopify automated refresh flow.

## Files added

```text
sql/marts/fct_cross_channel_orders.sql
sql/analysis/cross_channel_revenue_daily.sql
sql/analysis/cross_channel_revenue_daily_pivot.sql
sql/validation/cross_channel_revenue_validation.sql
docs/milestones/milestone-46-cross-channel-revenue-model-mvp.md
```

## Model layer

### `marts.fct_cross_channel_orders`

Grain:

```text
one row per channel order
```

Purpose:

- Creates the first reusable cross-channel order fact.
- Combines Shopify order facts with Etsy receipt/payment landing data.
- Uses channel-aware order keys to avoid collisions.
- Preserves source-specific revenue fields and edge-case flags.

Key fields:

```text
channel
channel_order_id
cross_channel_order_key
source_order_id
channel_customer_key
channel_customer_key_type
order_created_at
order_paid_at
order_date
financial_status
fulfillment_status
is_cancelled
has_refund
is_suspect_historical_timing
currency
subtotal_amount
discount_amount
shipping_amount
tax_amount
gross_amount
refund_amount
fee_amount
payment_gross_amount
payment_fee_amount
payment_net_amount
net_revenue_after_refunds
channel_reported_net_amount
total_items
line_item_count
distinct_sku_count
source_table
landing_run_id
landing_loaded_at
source_edge_case_notes
```

Channel key pattern:

```text
shopify:<order_number>
etsy:<receipt_id>
```

Shopify source:

```text
marts.fct_orders
```

Etsy sources:

```text
raw_load.etsy_receipts_api_latest
raw_load.etsy_receipt_transactions_api_latest
raw_load.etsy_receipt_payments_api_latest
```

### `marts.anl_cross_channel_revenue_daily`

Grain:

```text
one row per order_date and channel
```

Purpose:

- Long-format BI-friendly daily revenue view.
- Includes one row per date/channel plus an `all` channel row.
- Supports channel filtering and daily revenue comparison.

Channels:

```text
shopify
etsy
all
```

### `marts.anl_cross_channel_revenue_daily_pivot`

Grain:

```text
one row per order_date
```

Purpose:

- Business-readable side-by-side daily comparison.
- Shows Shopify, Etsy, and total revenue metrics on the same row.
- Focuses on the date range where Etsy landing data exists.

Example metric groups:

```text
shopify_completed_orders
shopify_gross_revenue
shopify_net_revenue_after_refunds

etsy_completed_orders
etsy_gross_revenue
etsy_fee_amount
etsy_net_revenue_after_refunds

total_completed_orders
total_gross_revenue
total_net_revenue_after_refunds
etsy_gross_revenue_share
shopify_gross_revenue_share
```

## Validation

Validation file:

```text
sql/validation/cross_channel_revenue_validation.sql
```

Validation covers:

- cross-channel order mart row count
- duplicate cross-channel order keys
- null required channel/order/date fields
- Shopify row count compared to trusted Shopify order fact
- Etsy row count compared to Etsy receipt landing table
- Shopify and Etsy channel coverage
- long-format daily `all` rows compared to Shopify plus Etsy channel rows
- daily pivot totals compared to long-format daily rows
- Shopify pivot metrics compared to Shopify long-format rows
- Etsy pivot metrics compared to Etsy long-format rows
- retained Etsy edge-case orders
- channel-level order and revenue summary

## Validation result

Validation completed with:

```text
FAIL: 0
REVIEW: 0
```

The validation confirmed:

- Shopify and Etsy are both present in the cross-channel order fact.
- Cross-channel order keys are unique.
- Required channel/order/date fields are populated.
- Shopify order counts match the trusted Shopify order fact.
- Etsy order counts match the Etsy receipt landing table.
- Daily all-channel rows equal Shopify plus Etsy channel rows.
- Daily pivot rows match the long-format daily view.
- Etsy edge cases are retained and flagged.

## Sanity-check result

Cross-channel order fact summary:

```text
etsy:
  orders: 173
  date range: 2026-04-19 to 2026-05-18
  gross amount: 11149.02
  refund amount: 417.88
  net revenue after refunds: 10731.14
  fee amount: 367.42
  edge-case orders: 4

shopify:
  orders: 15553
  date range: 2021-01-31 to 2026-05-18
  gross amount: 1158858.43
  refund amount: 15121.35
  net revenue after refunds: 1143737.08
  fee amount: null
  edge-case orders: 0
```

Daily analysis summary:

```text
all:
  daily rows: 1915
  submitted orders: 15726
  completed orders: 15631
  gross revenue: 1163428.70
  refunded amount: 9360.19
  fee amount: 367.42
  net revenue after refunds: 1154068.51
  edge-case orders: 4

etsy:
  daily rows: 30
  submitted orders: 173
  completed orders: 169
  gross revenue: 10837.69
  refunded amount: 147.69
  fee amount: 367.42
  net revenue after refunds: 10690.00
  edge-case orders: 4

shopify:
  daily rows: 1915
  submitted orders: 15553
  completed orders: 15462
  gross revenue: 1152591.01
  refunded amount: 9212.50
  fee amount: 0.00
  net revenue after refunds: 1143378.51
  edge-case orders: 0
```

## Implementation notes

Shopify revenue uses the existing trusted `marts.fct_orders` model and excludes suspect historical timing rows.

Etsy revenue uses receipt-level order data, transaction-level item counts, and payment-level fee/net context from the Milestone 45 landing tables.

The model uses channel-scoped customer keys but does not merge Shopify and Etsy customers into a shared customer identity.

The model uses channel-aware order keys so Shopify and Etsy order identifiers cannot collide.

The side-by-side daily pivot is limited to the Etsy landing date range, which makes it useful for immediate Shopify-versus-Etsy comparison over the period where both channels have available data.

## Outcome

Milestone 46 successfully created the first validated cross-channel revenue layer for Mischief Made Analytics.

The project now supports:

- order-level Shopify plus Etsy revenue modeling
- daily revenue by channel
- all-channel daily revenue totals
- side-by-side Shopify/Etsy daily comparison
- channel-aware order keys
- retained Etsy source edge-case flags

## Next milestone

Milestone 47 - Etsy Historical Backfill MVP

Planned focus:

- Backfill Etsy order data to match the trusted Shopify modeling window beginning on 2021-01-31.
- Extend the Etsy landing script to support explicit historical date ranges.
- Load Etsy receipts, receipt transactions, and receipt payments across the trusted historical period.
- Preserve the existing isolated `raw_load` landing pattern.
- Validate historical Etsy coverage, duplicate keys, required fields, missing payment records, blank SKUs, and date ranges.
- Rebuild and revalidate the cross-channel revenue model using the expanded Etsy history.
- Keep customer identity resolution, product-family harmonization, full payout reconciliation, and dashboarding out of scope for this milestone.

This milestone comes before the Business Dashboard MVP because the dashboard should not compare multi-year Shopify history against only 30 days of Etsy data. Historical Etsy coverage is needed for trustworthy cross-channel trends, channel mix, and business-facing revenue reporting.

After the Etsy historical backfill is validated, the next milestone will be:

Milestone 48 - Business Dashboard MVP
