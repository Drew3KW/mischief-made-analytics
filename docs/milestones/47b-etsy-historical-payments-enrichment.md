# Milestone 47B - Etsy Historical Payments Enrichment

## Summary

Milestone 47B completed historical Etsy receipt payment enrichment and added ongoing Etsy recent refresh orchestration.

This milestone extended the Etsy integration beyond receipt and transaction history by backfilling receipt payment records, promoting validated payment candidates into the latest Etsy payment landing table, catching up recent Etsy data, and adding a scheduled Airflow DAG to keep Etsy and cross-channel revenue outputs current.

## Why this milestone mattered

After Milestone 47A, Etsy receipts and receipt transactions were historically backfilled, but payment coverage was limited to the first manually loaded window.

Before 47B:

```text
Etsy receipts: 16,496
Etsy receipt transactions: 23,422
Etsy receipt payments: 273
Receipts missing payments: 16,223
```

The cross-channel revenue model still worked because receipt totals provided historical Etsy revenue, but payment-related fields were mostly unavailable after 2021-03-01.

47B improved Etsy financial coverage by adding historical receipt payment records and keeping recent Etsy data refreshed going forward.

## Added files

```text
dags/mm_etsy_historical_payments_backfill_mvp.py
dags/mm_etsy_recent_refresh_mvp.py
scripts/etsy_payments_backfill.py
sql/raw/create_etsy_historical_payment_backfill_batches.sql
sql/raw/create_etsy_payment_backfill_candidate_tables.sql
sql/raw/promote_etsy_payment_backfill_candidates_to_latest.sql
sql/raw/promote_etsy_recent_catchup_candidates_to_latest.sql
```

## Implementation

### Historical payment batch state

Added a payment-specific state table:

```text
raw_load.etsy_historical_payment_backfill_batches
```

The table tracks receipt-ID batches for payment enrichment with statuses such as:

```text
PENDING
RUNNING
COMPLETE
RATE_LIMIT
FAILED
```

The backfill used receipt-ID batches rather than date chunks because Etsy receipt payments are fetched one receipt at a time.

### Payment candidate and skipped-receipt tables

Added shared candidate/audit tables:

```text
raw_load.etsy_receipt_payments_api_payment_backfill_candidate
raw_load.etsy_receipt_payments_api_payment_backfill_skipped_receipts
```

Successful payment rows append to the candidate table.

Receipt-level Etsy 404 responses are recorded as skipped receipts rather than treated as failures.

### Payment backfill script

Added:

```text
scripts/etsy_payments_backfill.py
```

The script:

- processes one batch at a time
- fetches receipt payment records from the Etsy API
- appends successful payment rows to the shared candidate table
- records skipped 404 receipt IDs
- retries per-second throttling
- exits cleanly on true Etsy daily rate limits
- avoids reprocessing receipt IDs already present in the candidate or skipped tables

### Historical payment backfill DAG

Added:

```text
dags/mm_etsy_historical_payments_backfill_mvp.py
```

The DAG:

- repeatedly processes available payment batches
- marks batches as running, complete, failed, or rate-limited
- resumes from a `RATE_LIMIT` batch on the next run
- lets the Etsy API determine whether the rolling daily quota has recovered
- stops cleanly when the daily API limit is reached

The historical payment backfill completed with:

```text
163 COMPLETE batches
16,223 receipt IDs processed
16,093 payment rows captured
130 skipped 404 receipts
0 zero-payment responses
```

The accounting matched exactly:

```text
16,093 payment rows + 130 skipped 404 receipts = 16,223 processed receipt IDs
```

### Payment promotion

Added:

```text
sql/raw/promote_etsy_payment_backfill_candidates_to_latest.sql
```

The promotion script:

- asserts that all payment backfill batches are complete
- backs up the existing latest payment table
- unions existing latest payment rows with backfilled candidate rows
- deduplicates by `payment_id`
- replaces `raw_load.etsy_receipt_payments_api_latest`

After promotion, remaining missing payment coverage matched the skipped 404 receipt set.

### Recent Etsy catch-up

After historical payment promotion, all Etsy latest tables were current only through the historical backfill window. A recent catch-up load was run to bring Etsy receipts, transactions, and payments current.

Added:

```text
sql/raw/promote_etsy_recent_catchup_candidates_to_latest.sql
```

The script promotes recent catch-up candidate tables into the current latest Etsy landing tables with backup and deduplication.

### Ongoing Etsy recent refresh DAG

Added:

```text
dags/mm_etsy_recent_refresh_mvp.py
```

This is now the ongoing Etsy refresh DAG.

It runs a rolling recent Etsy landing window, promotes the recent candidates into latest Etsy landing tables, validates Etsy landing, rebuilds cross-channel revenue outputs, and runs cross-channel validation.

Flow:

```text
Etsy recent API landing
-> recent candidate promotion to latest
-> Etsy landing validation gate
-> fct_cross_channel_orders
-> cross_channel_revenue_daily
-> cross_channel_revenue_daily_pivot
-> cross-channel validation gate
```

The historical Etsy backfill DAGs were paused after completion. The recent refresh DAG remains active.

## Validation

Final validation completed successfully.

Validation covered:

- payment candidate uniqueness
- skipped receipt accounting
- historical batch completion
- latest payment promotion
- remaining missing payment coverage
- Etsy landing validation
- cross-channel revenue validation
- scheduled Etsy recent refresh DAG execution

No validation `FAIL` rows remained.

## Result

Milestone 47B completed the Etsy payment enrichment layer and added ongoing Etsy refresh orchestration.

The project now has an automated Shopify + Etsy revenue pipeline for the current scope:

```text
Shopify API refresh
-> canonical Shopify raw tables
-> warehouse refresh

Etsy API recent refresh
-> canonical Etsy latest landing tables
-> cross-channel mart and analysis refresh

Shopify + Etsy
-> fct_cross_channel_orders
-> cross_channel_revenue_daily
-> cross_channel_revenue_daily_pivot
-> validation gates
```

This provides the foundation for the next milestone: Business Dashboard MVP.
