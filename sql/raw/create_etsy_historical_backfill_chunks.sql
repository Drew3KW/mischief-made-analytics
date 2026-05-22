-- sql/raw/create_etsy_historical_backfill_chunks.sql
-- Purpose:
-- Create and seed the Etsy historical backfill state table.
--
-- Notes:
-- - This table lets Airflow process one backfill chunk at a time.
-- - The first chunk is marked COMPLETE because it was manually loaded before automation.
-- - Later chunks remain PENDING until processed by the backfill DAG.
-- - This state table tracks receipt/transaction backfill only for 47A.
-- - Payment enrichment is deferred to 47B.

CREATE TABLE IF NOT EXISTS `mischief-made-analytics.raw_load.etsy_historical_backfill_chunks` (
    chunk_id STRING,
    chunk_start_date DATE,
    chunk_end_date DATE,
    chunk_status STRING,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    receipt_row_count INT64,
    transaction_row_count INT64,
    payment_row_count INT64,
    skipped_payment_count INT64,
    error_message STRING,
    updated_at TIMESTAMP
);

INSERT INTO `mischief-made-analytics.raw_load.etsy_historical_backfill_chunks` (
    chunk_id,
    chunk_start_date,
    chunk_end_date,
    chunk_status,
    started_at,
    completed_at,
    receipt_row_count,
    transaction_row_count,
    payment_row_count,
    skipped_payment_count,
    error_message,
    updated_at
)

WITH date_settings AS (
    SELECT
        DATE '2021-01-31' AS backfill_start_date,
        CURRENT_DATE('America/Los_Angeles') AS backfill_end_date,
        30 AS chunk_days
),

chunk_offsets AS (
    SELECT
        offset_days
    FROM date_settings,
    UNNEST(
        GENERATE_ARRAY(
            0,
            DATE_DIFF(backfill_end_date, backfill_start_date, DAY),
            chunk_days
        )
    ) AS offset_days
),

chunks AS (
    SELECT
        FORMAT_DATE(
            '%Y%m%d',
            DATE_ADD(ds.backfill_start_date, INTERVAL co.offset_days DAY)
        ) AS chunk_id,

        DATE_ADD(ds.backfill_start_date, INTERVAL co.offset_days DAY) AS chunk_start_date,

        LEAST(
            DATE_ADD(
                ds.backfill_start_date,
                INTERVAL co.offset_days + ds.chunk_days - 1 DAY
            ),
            ds.backfill_end_date
        ) AS chunk_end_date

    FROM date_settings AS ds
    CROSS JOIN chunk_offsets AS co
),

seed_rows AS (
    SELECT
        chunk_id,
        chunk_start_date,
        chunk_end_date,

        CASE
            WHEN chunk_start_date = DATE '2021-01-31'
             AND chunk_end_date = DATE '2021-03-01'
                THEN 'COMPLETE'
            ELSE 'PENDING'
        END AS chunk_status,

        CASE
            WHEN chunk_start_date = DATE '2021-01-31'
             AND chunk_end_date = DATE '2021-03-01'
                THEN CURRENT_TIMESTAMP()
            ELSE CAST(NULL AS TIMESTAMP)
        END AS started_at,

        CASE
            WHEN chunk_start_date = DATE '2021-01-31'
             AND chunk_end_date = DATE '2021-03-01'
                THEN CURRENT_TIMESTAMP()
            ELSE CAST(NULL AS TIMESTAMP)
        END AS completed_at,

        CASE
            WHEN chunk_start_date = DATE '2021-01-31'
             AND chunk_end_date = DATE '2021-03-01'
                THEN 274
            ELSE CAST(NULL AS INT64)
        END AS receipt_row_count,

        CASE
            WHEN chunk_start_date = DATE '2021-01-31'
             AND chunk_end_date = DATE '2021-03-01'
                THEN 402
            ELSE CAST(NULL AS INT64)
        END AS transaction_row_count,

        CASE
            WHEN chunk_start_date = DATE '2021-01-31'
             AND chunk_end_date = DATE '2021-03-01'
                THEN 273
            ELSE CAST(NULL AS INT64)
        END AS payment_row_count,

        CASE
            WHEN chunk_start_date = DATE '2021-01-31'
             AND chunk_end_date = DATE '2021-03-01'
                THEN 1
            ELSE CAST(NULL AS INT64)
        END AS skipped_payment_count,

        CAST(NULL AS STRING) AS error_message,
        CURRENT_TIMESTAMP() AS updated_at

    FROM chunks
)

SELECT
    seed_rows.chunk_id,
    seed_rows.chunk_start_date,
    seed_rows.chunk_end_date,
    seed_rows.chunk_status,
    seed_rows.started_at,
    seed_rows.completed_at,
    seed_rows.receipt_row_count,
    seed_rows.transaction_row_count,
    seed_rows.payment_row_count,
    seed_rows.skipped_payment_count,
    seed_rows.error_message,
    seed_rows.updated_at
FROM seed_rows
WHERE NOT EXISTS (
    SELECT 1
    FROM `mischief-made-analytics.raw_load.etsy_historical_backfill_chunks` AS existing
    WHERE existing.chunk_id = seed_rows.chunk_id
);