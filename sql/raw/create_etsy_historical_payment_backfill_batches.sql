-- sql/raw/create_etsy_historical_payment_backfill_batches.sql
-- Purpose:
-- Create and seed the Etsy historical payment backfill state table.
--
-- Notes:
-- - This table lets Airflow process Etsy receipt payment enrichment in
--   controlled receipt-ID batches.
-- - Payment enrichment is API-call-bound because the payment endpoint is
--   fetched per receipt.
-- - Batches are seeded from receipts currently missing payment coverage.
-- - Existing payment coverage in raw_load.etsy_receipt_payments_api_latest
--   is preserved and excluded from the initial backfill queue.
-- - 404 payment fetches should be tracked as skipped, not treated as failed
--   batches.
-- - Real Etsy 429 responses should stop the DAG gracefully as RATE_LIMIT.

CREATE TABLE IF NOT EXISTS `mischief-made-analytics.raw_load.etsy_historical_payment_backfill_batches` (
    batch_id STRING,
    batch_sequence INT64,
    batch_start_position INT64,
    batch_end_position INT64,
    batch_receipt_count INT64,
    min_receipt_created_date DATE,
    max_receipt_created_date DATE,
    batch_status STRING,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    payment_row_count INT64,
    skipped_404_count INT64,
    zero_payment_response_count INT64,
    error_message STRING,
    updated_at TIMESTAMP
);

INSERT INTO `mischief-made-analytics.raw_load.etsy_historical_payment_backfill_batches` (
    batch_id,
    batch_sequence,
    batch_start_position,
    batch_end_position,
    batch_receipt_count,
    min_receipt_created_date,
    max_receipt_created_date,
    batch_status,
    started_at,
    completed_at,
    payment_row_count,
    skipped_404_count,
    zero_payment_response_count,
    error_message,
    updated_at
)
WITH settings AS (
    SELECT
        100 AS receipts_per_batch
),

existing_payment_receipts AS (
    SELECT DISTINCT
        receipt_id
    FROM `mischief-made-analytics.raw_load.etsy_receipt_payments_api_latest`
    WHERE receipt_id IS NOT NULL
),

receipt_universe AS (
    SELECT
        receipts.receipt_id,
        DATE(
            TIMESTAMP_SECONDS(
                COALESCE(receipts.created_timestamp, receipts.create_timestamp)
            )
        ) AS receipt_created_date
    FROM `mischief-made-analytics.raw_load.etsy_receipts_api_latest` AS receipts
    LEFT JOIN existing_payment_receipts AS payments
        ON receipts.receipt_id = payments.receipt_id
    WHERE receipts.receipt_id IS NOT NULL
      AND payments.receipt_id IS NULL
      AND COALESCE(receipts.created_timestamp, receipts.create_timestamp) IS NOT NULL
),

numbered_receipts AS (
    SELECT
        receipt_id,
        receipt_created_date,
        ROW_NUMBER() OVER (
            ORDER BY receipt_created_date, receipt_id
        ) AS receipt_position
    FROM receipt_universe
),

batched_receipts AS (
    SELECT
        DIV(receipt_position - 1, settings.receipts_per_batch) + 1 AS batch_sequence,
        receipt_position,
        receipt_created_date
    FROM numbered_receipts
    CROSS JOIN settings
),

seed_rows AS (
    SELECT
        CONCAT(
            'etsy_payment_backfill_',
            LPAD(CAST(batch_sequence AS STRING), 5, '0')
        ) AS batch_id,
        batch_sequence,
        MIN(receipt_position) AS batch_start_position,
        MAX(receipt_position) AS batch_end_position,
        COUNT(*) AS batch_receipt_count,
        MIN(receipt_created_date) AS min_receipt_created_date,
        MAX(receipt_created_date) AS max_receipt_created_date,
        'PENDING' AS batch_status,
        CAST(NULL AS TIMESTAMP) AS started_at,
        CAST(NULL AS TIMESTAMP) AS completed_at,
        CAST(NULL AS INT64) AS payment_row_count,
        CAST(NULL AS INT64) AS skipped_404_count,
        CAST(NULL AS INT64) AS zero_payment_response_count,
        CAST(NULL AS STRING) AS error_message,
        CURRENT_TIMESTAMP() AS updated_at
    FROM batched_receipts
    GROUP BY batch_sequence
)

SELECT
    seed_rows.batch_id,
    seed_rows.batch_sequence,
    seed_rows.batch_start_position,
    seed_rows.batch_end_position,
    seed_rows.batch_receipt_count,
    seed_rows.min_receipt_created_date,
    seed_rows.max_receipt_created_date,
    seed_rows.batch_status,
    seed_rows.started_at,
    seed_rows.completed_at,
    seed_rows.payment_row_count,
    seed_rows.skipped_404_count,
    seed_rows.zero_payment_response_count,
    seed_rows.error_message,
    seed_rows.updated_at
FROM seed_rows
WHERE NOT EXISTS (
    SELECT 1
    FROM `mischief-made-analytics.raw_load.etsy_historical_payment_backfill_batches` AS existing
    WHERE existing.batch_id = seed_rows.batch_id
);