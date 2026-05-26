-- sql/raw/promote_etsy_recent_catchup_candidates_to_latest.sql
-- Purpose:
-- Promote recent Etsy catch-up candidate rows into the current raw_load Etsy
-- latest landing tables.
--
-- Notes:
-- - Run after validating recent_catchup_candidate tables.
-- - Existing latest tables are backed up before replacement.
-- - Latest tables are rebuilt from existing latest plus catch-up candidate rows.
-- - Deduplication keeps the most recently loaded row per source key.

ASSERT (
    SELECT COUNT(*)
    FROM (
        SELECT
            receipt_id
        FROM `mischief-made-analytics.raw_load.etsy_receipts_api_recent_catchup_candidate`
        GROUP BY receipt_id
        HAVING COUNT(*) > 1
    )
) = 0
AS 'Cannot promote Etsy recent catch-up: duplicate receipt_id values found.';

ASSERT (
    SELECT COUNT(*)
    FROM (
        SELECT
            transaction_id
        FROM `mischief-made-analytics.raw_load.etsy_receipt_transactions_api_recent_catchup_candidate`
        GROUP BY transaction_id
        HAVING COUNT(*) > 1
    )
) = 0
AS 'Cannot promote Etsy recent catch-up: duplicate transaction_id values found.';

ASSERT (
    SELECT COUNT(*)
    FROM (
        SELECT
            payment_id
        FROM `mischief-made-analytics.raw_load.etsy_receipt_payments_api_recent_catchup_candidate`
        WHERE payment_id IS NOT NULL
        GROUP BY payment_id
        HAVING COUNT(*) > 1
    )
) = 0
AS 'Cannot promote Etsy recent catch-up: duplicate payment_id values found.';

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.etsy_receipts_api_pre_recent_catchup_backup_latest` AS
SELECT
    *
FROM `mischief-made-analytics.raw_load.etsy_receipts_api_latest`;

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.etsy_receipt_transactions_api_pre_recent_catchup_backup_latest` AS
SELECT
    *
FROM `mischief-made-analytics.raw_load.etsy_receipt_transactions_api_latest`;

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.etsy_receipt_payments_api_pre_recent_catchup_backup_latest` AS
SELECT
    *
FROM `mischief-made-analytics.raw_load.etsy_receipt_payments_api_latest`;

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.etsy_receipts_api_latest` AS
WITH combined_rows AS (
    SELECT
        *
    FROM `mischief-made-analytics.raw_load.etsy_receipts_api_pre_recent_catchup_backup_latest`

    UNION ALL

    SELECT
        *
    FROM `mischief-made-analytics.raw_load.etsy_receipts_api_recent_catchup_candidate`
),

deduplicated_rows AS (
    SELECT
        * EXCEPT(row_number)
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY receipt_id
                ORDER BY landing_loaded_at DESC
            ) AS row_number
        FROM combined_rows
    )
    WHERE row_number = 1
)

SELECT
    *
FROM deduplicated_rows;

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.etsy_receipt_transactions_api_latest` AS
WITH combined_rows AS (
    SELECT
        *
    FROM `mischief-made-analytics.raw_load.etsy_receipt_transactions_api_pre_recent_catchup_backup_latest`

    UNION ALL

    SELECT
        *
    FROM `mischief-made-analytics.raw_load.etsy_receipt_transactions_api_recent_catchup_candidate`
),

deduplicated_rows AS (
    SELECT
        * EXCEPT(row_number)
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY transaction_id
                ORDER BY landing_loaded_at DESC
            ) AS row_number
        FROM combined_rows
    )
    WHERE row_number = 1
)

SELECT
    *
FROM deduplicated_rows;

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.etsy_receipt_payments_api_latest` AS
WITH combined_rows AS (
    SELECT
        *
    FROM `mischief-made-analytics.raw_load.etsy_receipt_payments_api_pre_recent_catchup_backup_latest`

    UNION ALL

    SELECT
        *
    FROM `mischief-made-analytics.raw_load.etsy_receipt_payments_api_recent_catchup_candidate`
),

deduplicated_rows AS (
    SELECT
        * EXCEPT(row_number)
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY payment_id
                ORDER BY landing_loaded_at DESC
            ) AS row_number
        FROM combined_rows
        WHERE payment_id IS NOT NULL
    )
    WHERE row_number = 1
)

SELECT
    *
FROM deduplicated_rows;