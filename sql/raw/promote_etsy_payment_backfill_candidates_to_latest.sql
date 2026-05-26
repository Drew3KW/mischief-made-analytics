-- sql/raw/promote_etsy_payment_backfill_candidates_to_latest.sql
-- Purpose:
-- Promote deduplicated Etsy historical payment backfill candidate rows to the
-- current raw_load Etsy receipt payments latest table.
--
-- Notes:
-- - Run this only after every payment backfill batch is COMPLETE.
-- - Existing latest payment rows are preserved and unioned with the 47B
--   payment candidate rows.
-- - Existing latest payment rows are backed up before replacement.
-- - Deduplication keeps the most recently loaded row per payment_id.
-- - This script does not promote skipped receipt details; those remain as
--   operational audit data in raw_load.

ASSERT (
    SELECT COUNT(*)
    FROM `mischief-made-analytics.raw_load.etsy_historical_payment_backfill_batches`
    WHERE batch_status != 'COMPLETE'
) = 0
AS 'Cannot promote Etsy payment backfill candidates: not all payment backfill batches are COMPLETE.';

ASSERT (
    SELECT COUNT(*)
    FROM `mischief-made-analytics.raw_load.etsy_receipt_payments_api_payment_backfill_candidate`
    WHERE payment_id IS NULL
) = 0
AS 'Cannot promote Etsy payment backfill candidates: candidate table contains NULL payment_id values.';

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.etsy_receipt_payments_api_pre_payment_backfill_backup_latest` AS
SELECT
    *
FROM `mischief-made-analytics.raw_load.etsy_receipt_payments_api_latest`;

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.etsy_receipt_payments_api_latest` AS
WITH combined_payment_rows AS (
    SELECT
        *
    FROM `mischief-made-analytics.raw_load.etsy_receipt_payments_api_pre_payment_backfill_backup_latest`

    UNION ALL

    SELECT
        *
    FROM `mischief-made-analytics.raw_load.etsy_receipt_payments_api_payment_backfill_candidate`
),

deduplicated_payment_rows AS (
    SELECT
        * EXCEPT(row_number)
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY payment_id
                ORDER BY landing_loaded_at DESC
            ) AS row_number
        FROM combined_payment_rows
    )
    WHERE row_number = 1
)

SELECT
    *
FROM deduplicated_payment_rows;