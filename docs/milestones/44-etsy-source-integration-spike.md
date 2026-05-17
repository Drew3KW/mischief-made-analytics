# Milestone 44 - Etsy Source Integration Spike

## Goal

Explore Etsy as the next source system for Mischief Made Analytics and define the path toward an Etsy landing MVP.

This milestone was intentionally scoped as a spike, not a production integration.

## Why this matters

Etsy is a major Mischief Made sales channel. A Shopify-only dashboard would be incomplete and could lead to misleading business conclusions.

Before building cross-channel models or dashboards, the warehouse needs a clear plan for bringing Etsy order, transaction, payment, and fee data into the project safely.

## Scope

Completed:

- Registered and received approval for an Etsy Open API application.
- Added placeholder Etsy environment variables to `.env.example`.
- Added a local Etsy API probe script:
  - `scripts/etsy_api_probe.py`
- Added local-only Etsy spike output path:
  - `local_data/etsy_api_spike/`
- Tested approved Etsy API credentials with a ping probe.
- Completed OAuth locally using a manual authorization code flow.
- Retrieved authenticated shop/user identifiers.
- Retrieved local sample data for:
  - receipts
  - receipt transactions
  - receipt payments
  - ledger entries
- Generated a share-safe field inventory.
- Documented Etsy source shapes and landing table design.

## Non-goals

Not included:

- No production warehouse table changes.
- No Shopify refresh flow changes.
- No Etsy Airflow production DAG.
- No Etsy staging, marts, or analysis models.
- No cross-channel revenue model yet.
- No committed credentials, tokens, or local API output.

## Files added or updated

Added:

- `docs/spikes/etsy-source-integration-spike.md`
- `docs/milestones/milestone-44-etsy-source-integration-spike.md`
- `scripts/etsy_api_probe.py`

Updated:

- `.env.example`
- `README.md`

Local-only outputs created but not committed:

- `local_data/etsy_api_spike/ping.json`
- `local_data/etsy_api_spike/me.json`
- `local_data/etsy_api_spike/receipts_sample.json`
- `local_data/etsy_api_spike/receipt_<receipt_id>_transactions_sample.json`
- `local_data/etsy_api_spike/receipt_<receipt_id>_payment_sample.json`
- `local_data/etsy_api_spike/ledger_entries_sample.json`
- `local_data/etsy_api_spike/field_inventory.md`
- `local_data/etsy_api_spike/oauth_state.json`
- `local_data/etsy_api_spike/oauth_token.json`

## Findings

### Authentication

Etsy API access requires:

- approved Etsy API keystring
- shared secret
- registered redirect URI
- OAuth access token
- OAuth refresh token

Real credentials and tokens are stored only in local `.env` or local spike output.

### Shop identification

The authenticated `me` probe returned:

- `shop_id`
- `user_id`

This confirmed the local OAuth token can access the intended Etsy shop context.

### Receipts

Receipts are the Etsy order/header source.

They include:

- receipt identifiers
- buyer identifiers
- order status
- created and updated timestamps
- shipping status
- discount fields
- subtotal, grand total, shipping, tax, and VAT fields
- refunds
- shipments
- nested transactions

Future landing grain:

- one row per receipt

Future landing table:

- `raw_load.etsy_receipts_api`

### Receipt transactions

Receipt transactions are the Etsy order-item source.

They include:

- transaction ID
- receipt ID
- listing ID
- product ID
- SKU
- title
- quantity
- item price
- shipping cost
- coupon fields
- variation fields

Future landing grain:

- one row per receipt transaction

Future landing table:

- `raw_load.etsy_receipt_transactions_api`

### Receipt payments

Receipt payments provide Etsy payment, fee, net, and adjustment fields.

They include:

- payment ID
- receipt ID
- gross amount
- fees
- net amount
- adjusted gross
- adjusted fees
- adjusted net
- posted gross
- posted fees
- posted net
- payment adjustments

Future landing grain:

- one row per receipt payment

Future landing table:

- `raw_load.etsy_receipt_payments_api`

### Ledger entries

Ledger entries support accounting and payout reconciliation. They are not order or product revenue rows.

They include:

- ledger entry ID
- ledger type
- reference ID
- reference type
- amount
- balance
- description
- payment adjustments

Future reconciliation table:

- `raw_load.etsy_ledger_entries_api`

## Initial modeling decisions

First-pass mapping:

| Warehouse concept | Etsy source |
|---|---|
| Channel | static value: `etsy` |
| Order key | `receipt_id` |
| Order-item key | `transaction_id` |
| Customer key | buyer email if usable; otherwise channel-scoped buyer user ID |
| Product key | SKU first if reliable; otherwise listing ID or product ID |
| Order date | receipt created or paid timestamp |
| Gross revenue | compare receipt totals and payment gross |
| Shipping | receipt shipping total and/or transaction shipping cost |
| Tax | receipt tax and VAT fields |
| Refunds | receipt refunds plus payment adjustments |
| Fees | payment fee fields |
| Net revenue | payment net or adjusted net, after validation |

## Risks and cautions

- Etsy customer identity may not map cleanly to Shopify customer identity.
- Etsy net revenue needs careful validation against refunds, fees, and adjustments.
- Ledger entries are reconciliation rows, not product-level revenue rows.
- Raw Etsy data lands in isolated `raw_load` tables before semantic modeling.
- Etsy remains separate from the Shopify automated refresh flow until landing and validation are proven.

## Outcome

Milestone 44 proved that Etsy API access works and that the API exposes the core data shapes needed for an Etsy Orders Landing MVP.

The project can now proceed to isolated Etsy landing tables without touching production Shopify raw tables or the existing Shopify automated refresh flow.

## Next milestone

Milestone 45 - Etsy Orders Landing MVP

Milestone 45 scope:

- Build an isolated Etsy landing script or DAG.
- Land receipts to `raw_load`.
- Land receipt transactions to `raw_load`.
- Land receipt payments to `raw_load`.
- Add lightweight validation.
- Keep Etsy isolated from production warehouse models until landing is validated.
