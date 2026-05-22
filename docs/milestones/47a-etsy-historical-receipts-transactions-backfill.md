# Milestone 47A - Etsy Historical Receipts and Transactions Backfill

## Goal

Backfill Etsy receipt and receipt transaction history across the trusted Shopify modeling window.

This milestone extends Etsy coverage from a recent landing window to historical receipt and order-item coverage beginning on 2021-01-31.

## Why this matters

The first cross-channel revenue model proved that Shopify and Etsy could be modeled together, but Etsy initially covered only a recent 30-day window.

A business dashboard should not compare multi-year Shopify history against only recent Etsy history. This milestone fills the historical Etsy receipt and transaction gap before dashboarding.

## Scope

Completed:

- Extended `scripts/etsy_orders_landing.py` to support:
  - explicit `--start-date` and `--end-date`
  - chunked processing with `--chunk-days`
  - configurable table suffixes
  - append vs replace write modes
  - resumable progress output
  - safer rate-limit handling
- Added Etsy historical backfill state table SQL:
  - `sql/raw/create_etsy_historical_backfill_chunks.sql`
- Added Airflow DAG for historical receipt/transaction backfill:
  - `dags/mm_etsy_historical_backfill_mvp.py`
- Mounted local `scripts/` into the Airflow container.
- Passed local `.env` values into Airflow services for Etsy credentials.
- Processed all historical receipt/transaction chunks through Airflow.
- Promoted deduplicated backfill candidate tables to current Etsy `_latest` landing tables:
  - `sql/raw/promote_etsy_historical_backfill_candidates_to_latest.sql`
- Rebuilt and revalidated the cross-channel revenue models against the expanded Etsy history.

## Non-goals

Not included:

- No full Etsy payment backfill.
- No Etsy staging models.
- No Etsy product/listing catalog models.
- No cross-channel customer identity resolution.
- No Shopify/Etsy product-family harmonization.
- No full Etsy payout or accounting reconciliation.
- No dashboard build in this milestone.

## Files added or updated

Added:

```text
sql/raw/create_etsy_historical_backfill_chunks.sql
sql/raw/promote_etsy_historical_backfill_candidates_to_latest.sql
dags/mm_etsy_historical_backfill_mvp.py
```

Updated:

```text
scripts/etsy_orders_landing.py
docker-compose.yml
README.md
```

## Backfill design

The backfill uses a state table:

```text
raw_load.etsy_historical_backfill_chunks
```

Each row represents one historical date chunk.

The Airflow DAG processes chunks by:

```text
read next pending chunk
-> mark chunk running
-> run Etsy landing script for that date range
-> append results to backfill candidate tables
-> mark chunk complete
-> repeat until no pending chunks remain or a real rate limit occurs
```

The DAG uses `--skip-payments` for 47A. Payment enrichment is deferred to 47B.

## Backfill candidate tables

The historical backfill first writes to candidate tables:

```text
raw_load.etsy_receipts_api_backfill_candidate
raw_load.etsy_receipt_transactions_api_backfill_candidate
raw_load.etsy_receipt_payments_api_backfill_candidate
```

Candidate table results:

```text
receipts:     16,496 rows, 16,496 distinct keys, 2021-01-31 to 2026-05-20
transactions: 23,422 rows, 23,422 distinct keys, 2021-01-31 to 2026-05-20
payments:        273 rows,    273 distinct keys, 2021-01-31 to 2021-03-01
```

Duplicate key counts:

```text
receipts:     0
transactions: 0
payments:     0
```

## Promotion to latest tables

After validation, the backfill candidate tables were promoted to the current Etsy landing tables:

```text
raw_load.etsy_receipts_api_latest
raw_load.etsy_receipt_transactions_api_latest
raw_load.etsy_receipt_payments_api_latest
```

Existing latest tables were backed up before replacement.

Payments remain partial because historical payment enrichment is deferred.

## Validation results

### Etsy landing validation

Validation file:

```text
sql/validation/etsy_orders_landing_validation.sql
```

Result:

```text
PASS: 19
REVIEW: 2
INFO: 2
FAIL: 0
```

Key validated results:

```text
receipts=16,496
transactions=23,422
payments=273
date range=2021-01-31 to 2026-05-20
duplicate receipt_id=0
duplicate transaction_id=0
transactions missing parent receipt=0
receipts missing transactions=0
```

Review items:

```text
etsy_receipts_missing_payments = 16,223
etsy_transactions_blank_sku = 820
```

The missing payment records are expected because 47A intentionally backfilled receipts and transactions only. Blank SKUs are not a landing failure, but they matter for future product mapping.

### Cross-channel validation

Validation file:

```text
sql/validation/cross_channel_revenue_validation.sql
```

Result:

```text
FAIL: 0
REVIEW: 0
```

Key validated results:

```text
etsy orders=16,496
shopify orders=15,562
cross-channel order rows=32,058
duplicate cross-channel keys=0
null required keys/dates=0
```

Channel summary after backfill:

```text
etsy gross=941,456.61
etsy net after refunds=930,362.29

shopify gross=1,159,437.84
shopify net after refunds=1,144,316.49
```

## Outcome

Milestone 47A completed the historical Etsy receipt and transaction backfill across the trusted Shopify modeling window.

The cross-channel revenue model now uses multi-year Etsy order coverage instead of a 30-day Etsy window.

## Next milestone

Milestone 47B - Etsy Historical Payments Enrichment

Focus:

- Backfill Etsy payment records separately.
- Preserve the state-table-driven, resumable Airflow pattern.
- Enrich Etsy revenue with historical fee and payment net fields.
- Reduce missing payment edge cases in the cross-channel revenue model.
- Keep customer identity resolution, product-family harmonization, and dashboarding out of scope.
