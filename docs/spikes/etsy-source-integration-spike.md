# Etsy Source Integration Spike

## Goal

Explore the safest first path for integrating Etsy into the Mischief Made analytics warehouse.

This spike focuses on authentication, available Etsy API and CSV data, expected raw landing grains, and how Etsy concepts map to the existing Shopify-centered warehouse.

## Non-goals

- Do not modify production warehouse tables.
- Do not modify the Shopify automated refresh flow.
- Do not wire Etsy into the master Airflow refresh DAG.
- Do not create production Etsy staging, marts, or analysis models yet.
- Do not commit credentials, tokens, or local API output.

## Current Approach

Use an API-first, CSV-aware approach.

The Etsy Open API should be the preferred long-term automated ingestion path. Etsy CSV exports may still be useful for historical backfill, manual reconciliation, and validating early API outputs.

## Local spike artifacts

Committed files:

- `docs/spikes/etsy-source-integration-spike.md`
- `scripts/etsy_api_probe.py`
- `.env.example` placeholder updates for Etsy variables

Local-only output:

- `local_data/etsy_api_spike/`

This folder is ignored by Git and should not be committed.

## Required local environment variables

Real values should be stored only in local `.env`.

```bash
ETSY_API_KEYSTRING=your-etsy-api-keystring
ETSY_SHARED_SECRET=your-etsy-shared-secret
ETSY_REDIRECT_URI=your-registered-etsy-redirect-uri
ETSY_SHOP_ID=your-etsy-shop-id
ETSY_ACCESS_TOKEN=
ETSY_REFRESH_TOKEN=
```

## Probe commands

Test approved app credentials:

```bash
python scripts/etsy_api_probe.py ping
```

Generate an OAuth URL:

```bash
python scripts/etsy_api_probe.py auth-url
```

Exchange the OAuth authorization code for tokens:

```bash
python scripts/etsy_api_probe.py exchange-code "PASTE_CODE_HERE"
```

Fetch authenticated user and shop identifiers:

```bash
python scripts/etsy_api_probe.py me
```

Fetch receipt samples:

```bash
python scripts/etsy_api_probe.py receipts --days 30
```

Fetch receipt transaction and payment samples:

```bash
python scripts/etsy_api_probe.py receipt-transactions RECEIPT_ID
python scripts/etsy_api_probe.py receipt-payment RECEIPT_ID
```

Fetch recent ledger entries:

```bash
python scripts/etsy_api_probe.py ledger --days 30
```

## Spike results

The API key and shared secret were approved and successfully tested with the ping endpoint.

The OAuth flow was completed successfully using a manually copied authorization code from the registered redirect URI.

The authenticated `me` probe returned the expected shop and user identifiers:

- `shop_id`
- `user_id`

The receipt, transaction, payment, and ledger probes all returned local JSON samples and generated a field inventory.

## Observed API shapes

### Ping

Output file:

- `ping.json`

Observed fields:

- `application_id`

Purpose:

- Confirms approved app credentials and basic Etsy API connectivity.

### Authenticated user

Output file:

- `me.json`

Observed fields:

- `shop_id`
- `user_id`

Purpose:

- Confirms OAuth access and provides the Etsy shop ID needed for shop-scoped endpoints.

### Receipts

Output file:

- `receipts_sample.json`

Observed field count:

- 133 field paths

Likely grain:

- One row per Etsy receipt.
- Comparable to Shopify order/header grain.

Important observed concepts:

- `receipt_id`
- `buyer_email`
- `buyer_user_id`
- `seller_user_id`
- `create_timestamp`
- `created_timestamp`
- `update_timestamp`
- `updated_timestamp`
- `status`
- `is_paid`
- `is_shipped`
- `discount_amt`
- `subtotal`
- `grandtotal`
- `total_price`
- `total_shipping_cost`
- `total_tax_cost`
- `total_vat_cost`
- `refunds`
- `shipments`
- nested `transactions`

Receipts are the strongest candidate for Etsy order-header landing.

### Receipt transactions

Output file:

- `receipt_<receipt_id>_transactions_sample.json`

Observed field count:

- 45 field paths

Likely grain:

- One row per purchased listing transaction.
- Comparable to Shopify order-item grain.

Important observed concepts:

- `transaction_id`
- `receipt_id`
- `buyer_user_id`
- `seller_user_id`
- `listing_id`
- `product_id`
- `sku`
- `title`
- `quantity`
- `price`
- `shipping_cost`
- `buyer_coupon`
- `shop_coupon`
- `variations`

Receipt transactions are the strongest candidate for Etsy order-item landing.

### Receipt payments

Output file:

- `receipt_<receipt_id>_payment_sample.json`

Observed field count:

- 48 field paths

Likely grain:

- One row per payment record associated with a receipt.

Important observed concepts:

- `payment_id`
- `receipt_id`
- `shop_id`
- `buyer_user_id`
- `status`
- `currency`
- `buyer_currency`
- `shop_currency`
- `amount_gross`
- `amount_fees`
- `amount_net`
- `adjusted_gross`
- `adjusted_fees`
- `adjusted_net`
- `posted_gross`
- `posted_fees`
- `posted_net`
- `payment_adjustments`

Receipt payments are important for gross, fee, net, and adjustment modeling.

### Ledger entries

Output file:

- `ledger_entries_sample.json`

Observed field count:

- 18 field paths

Likely grain:

- One row per Etsy payment account ledger entry.

Important observed concepts:

- `entry_id`
- `ledger_id`
- `ledger_type`
- `reference_id`
- `reference_type`
- `amount`
- `balance`
- `description`
- `payment_adjustments`

Ledger entries are useful for payout and accounting reconciliation, but should not be treated as product/order revenue rows in the first cross-channel revenue model.

## Initial landing table recommendation

Milestone 45 should start with isolated API landing tables in `raw_load`:

```text
raw_load.etsy_receipts_api
raw_load.etsy_receipt_transactions_api
raw_load.etsy_receipt_payments_api
```

Ledger entries can be included if simple, but should be treated as optional for the first landing MVP:

```text
raw_load.etsy_ledger_entries_api
```

## Initial Shopify-to-Etsy concept map

| Existing concept | Shopify source | Etsy candidate |
|---|---|---|
| Channel | Shopify | Etsy |
| Order key | `order_number` | `receipt_id` |
| Order date | Shopify order created/paid date | receipt created/paid timestamp |
| Customer key | `customer_email` | buyer email if available; otherwise channel-scoped buyer user ID |
| Order-item key | Shopify line item ID | Etsy transaction ID |
| Product key | Shopify product/variant/SKU | SKU first if reliable; otherwise listing ID or product ID |
| Product title | Shopify product/title fields | transaction title or listing title |
| Quantity | line item quantity | transaction quantity |
| Gross revenue | order or line item totals | receipt totals and/or payment gross |
| Shipping | shipping total | receipt shipping total and/or transaction shipping cost |
| Tax | tax fields | receipt tax/VAT fields |
| Refunds | refund fields | receipt refunds plus payment adjustments |
| Fees | not core Shopify revenue model yet | Etsy payment fees |
| Net revenue | derived downstream | payment net or adjusted net, after validation |

## Important modeling cautions

- Do not treat ledger entries as order or product revenue rows.
- Do not choose a final Etsy net revenue definition until receipt totals, payment fields, adjustments, and refunds are reconciled.
- Do not assume Etsy customer identity will match Shopify customer identity.
- Use channel-scoped customer keys until cross-channel identity logic is deliberately designed.
- Preserve raw Etsy API fields in isolated landing tables before applying business semantics downstream.
- Keep Etsy ingestion separate from the Shopify automated refresh flow until the Etsy landing MVP has been validated.

## Recommended next milestone

Milestone 45 should build an isolated Etsy Orders Landing MVP.

Expected first scope:

- Fetch recent Etsy receipts.
- Flatten and land receipt/order-header records into `raw_load`.
- Flatten and land receipt transaction/order-item records into `raw_load`.
- Land receipt payment records into `raw_load`.
- Add lightweight landing validation.
- Keep all outputs isolated from production `raw`, `staging`, `marts`, and `analysis`.

Future work after Milestone 45:

- Etsy staging models
- Etsy order and order-item marts
- Shopify plus Etsy cross-channel revenue model
- Business dashboard MVP
- Optional Etsy ledger/payout reconciliation
