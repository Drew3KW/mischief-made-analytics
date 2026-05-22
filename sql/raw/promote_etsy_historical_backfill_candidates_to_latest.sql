-- sql/raw/promote_etsy_historical_backfill_candidates_to_latest.sql
-- Purpose:
-- Promote deduplicated Etsy historical backfill candidate tables to the current
-- raw_load Etsy API latest tables.
--
-- Notes:
-- - Receipts and transactions represent the completed 47A historical backfill.
-- - Payments are still partial and will be completed separately in 47B.
-- - Existing latest tables are backed up before replacement.
-- - Deduplication keeps the most recently loaded row per source key.

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.etsy_receipts_api_pre_historical_backfill_backup_latest` AS
SELECT *
FROM `mischief-made-analytics.raw_load.etsy_receipts_api_latest`;

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.etsy_receipt_transactions_api_pre_historical_backfill_backup_latest` AS
SELECT *
FROM `mischief-made-analytics.raw_load.etsy_receipt_transactions_api_latest`;

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.etsy_receipt_payments_api_pre_historical_backfill_backup_latest` AS
SELECT *
FROM `mischief-made-analytics.raw_load.etsy_receipt_payments_api_latest`;


CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.etsy_receipts_api_latest` AS

SELECT * EXCEPT(row_number)
FROM (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY receipt_id
            ORDER BY landing_loaded_at DESC
        ) AS row_number
    FROM `mischief-made-analytics.raw_load.etsy_receipts_api_backfill_candidate`
)
WHERE row_number = 1;


CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.etsy_receipt_transactions_api_latest` AS

SELECT * EXCEPT(row_number)
FROM (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY transaction_id
            ORDER BY landing_loaded_at DESC
        ) AS row_number
    FROM `mischief-made-analytics.raw_load.etsy_receipt_transactions_api_backfill_candidate`
)
WHERE row_number = 1;


CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.etsy_receipt_payments_api_latest` AS

SELECT * EXCEPT(row_number)
FROM (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY payment_id
            ORDER BY landing_loaded_at DESC
        ) AS row_number
    FROM `mischief-made-analytics.raw_load.etsy_receipt_payments_api_backfill_candidate`
)
WHERE row_number = 1;