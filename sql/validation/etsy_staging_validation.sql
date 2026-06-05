-- sql/validation/etsy_staging_validation.sql
-- Purpose:
-- Validate Etsy staging models for Milestone 49.
--
-- Scope:
-- - staging.stg_etsy_receipts
-- - staging.stg_etsy_receipt_transactions
-- - staging.stg_etsy_receipt_payments
--
-- Notes:
-- - Etsy payment rows are expected to be fewer than receipt rows because
--   some receipt payment endpoint calls returned 404s during payment enrichment.
-- - This validation checks staging shape, uniqueness, dates, and basic
--   referential integrity from transactions/payments back to receipts.

WITH receipts AS (
    SELECT *
    FROM `mischief-made-analytics.staging.stg_etsy_receipts`
),

transactions AS (
    SELECT *
    FROM `mischief-made-analytics.staging.stg_etsy_receipt_transactions`
),

payments AS (
    SELECT *
    FROM `mischief-made-analytics.staging.stg_etsy_receipt_payments`
),

receipt_shape AS (
    SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT receipt_id) AS distinct_receipt_count,
        COUNTIF(receipt_id IS NULL) AS null_receipt_id_count,
        COUNTIF(receipt_created_date IS NULL) AS null_receipt_created_date_count,
        MIN(receipt_created_date) AS min_receipt_created_date,
        MAX(receipt_created_date) AS max_receipt_created_date,
        COUNTIF(grandtotal < 0) AS negative_grandtotal_count,
        COUNTIF(total_price < 0) AS negative_total_price_count
    FROM receipts
),

transaction_shape AS (
    SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT transaction_id) AS distinct_transaction_count,
        COUNTIF(transaction_id IS NULL) AS null_transaction_id_count,
        COUNTIF(receipt_id IS NULL) AS null_receipt_id_count,
        COUNTIF(transaction_created_date IS NULL) AS null_transaction_created_date_count,
        MIN(transaction_created_date) AS min_transaction_created_date,
        MAX(transaction_created_date) AS max_transaction_created_date,
        COUNTIF(quantity < 0) AS negative_quantity_count,
        COUNTIF(item_price < 0) AS negative_item_price_count,
        COUNTIF(item_gross_amount < 0) AS negative_item_gross_amount_count
    FROM transactions
),

payment_shape AS (
    SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT payment_id) AS distinct_payment_count,
        COUNTIF(payment_id IS NULL) AS null_payment_id_count,
        COUNTIF(receipt_id IS NULL) AS null_receipt_id_count,
        COUNTIF(payment_created_date IS NULL) AS null_payment_created_date_count,
        MIN(payment_created_date) AS min_payment_created_date,
        MAX(payment_created_date) AS max_payment_created_date,
        COUNTIF(selected_gross_amount < 0) AS negative_selected_gross_count,
        COUNTIF(selected_fee_amount < 0) AS negative_selected_fee_count,
        COUNTIF(selected_net_amount IS NULL) AS null_selected_net_count
    FROM payments
),

transaction_receipt_integrity AS (
    SELECT
        COUNT(*) AS orphan_transaction_count
    FROM transactions AS t
    LEFT JOIN receipts AS r
        ON t.receipt_id = r.receipt_id
    WHERE r.receipt_id IS NULL
),

payment_receipt_integrity AS (
    SELECT
        COUNT(*) AS orphan_payment_count
    FROM payments AS p
    LEFT JOIN receipts AS r
        ON p.receipt_id = r.receipt_id
    WHERE r.receipt_id IS NULL
),

receipt_payment_coverage AS (
    SELECT
        COUNT(DISTINCT r.receipt_id) AS receipt_count,
        COUNT(DISTINCT p.receipt_id) AS receipts_with_payment_count,
        COUNT(DISTINCT r.receipt_id) - COUNT(DISTINCT p.receipt_id) AS receipts_without_payment_count
    FROM receipts AS r
    LEFT JOIN payments AS p
        ON r.receipt_id = p.receipt_id
),

validation_results AS (
    SELECT
        'stg_etsy_receipts_row_count' AS check_name,
        CAST(row_count AS STRING) AS result_value,
        '> 0' AS expected_value,
        CASE WHEN row_count > 0 THEN 'PASS' ELSE 'FAIL' END AS check_status,
        'Receipt staging table should contain rows.' AS notes
    FROM receipt_shape

    UNION ALL

    SELECT
        'stg_etsy_receipts_duplicate_key_count',
        CAST(row_count - distinct_receipt_count AS STRING),
        '0',
        CASE WHEN row_count - distinct_receipt_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Receipt staging table should have one row per receipt_id.'
    FROM receipt_shape

    UNION ALL

    SELECT
        'stg_etsy_receipts_null_key_count',
        CAST(null_receipt_id_count AS STRING),
        '0',
        CASE WHEN null_receipt_id_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Receipt IDs should not be null.'
    FROM receipt_shape

    UNION ALL

    SELECT
        'stg_etsy_receipts_null_created_date_count',
        CAST(null_receipt_created_date_count AS STRING),
        '0',
        CASE WHEN null_receipt_created_date_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Receipt created dates should not be null.'
    FROM receipt_shape

    UNION ALL

    SELECT
        'stg_etsy_receipts_date_range',
        CONCAT(CAST(min_receipt_created_date AS STRING), ' to ', CAST(max_receipt_created_date AS STRING)),
        'populated date range',
        CASE
            WHEN min_receipt_created_date IS NOT NULL
                AND max_receipt_created_date IS NOT NULL
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Receipt staging table should have a populated date range.'
    FROM receipt_shape

    UNION ALL

    SELECT
        'stg_etsy_receipts_negative_money_count',
        CAST(negative_grandtotal_count + negative_total_price_count AS STRING),
        '0',
        CASE WHEN negative_grandtotal_count + negative_total_price_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Receipt money fields should not be negative.'
    FROM receipt_shape

    UNION ALL

    SELECT
        'stg_etsy_transactions_row_count',
        CAST(row_count AS STRING),
        '> 0',
        CASE WHEN row_count > 0 THEN 'PASS' ELSE 'FAIL' END,
        'Transaction staging table should contain rows.'
    FROM transaction_shape

    UNION ALL

    SELECT
        'stg_etsy_transactions_duplicate_key_count',
        CAST(row_count - distinct_transaction_count AS STRING),
        '0',
        CASE WHEN row_count - distinct_transaction_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Transaction staging table should have one row per transaction_id.'
    FROM transaction_shape

    UNION ALL

    SELECT
        'stg_etsy_transactions_null_key_count',
        CAST(null_transaction_id_count AS STRING),
        '0',
        CASE WHEN null_transaction_id_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Transaction IDs should not be null.'
    FROM transaction_shape

    UNION ALL

    SELECT
        'stg_etsy_transactions_null_receipt_id_count',
        CAST(null_receipt_id_count AS STRING),
        '0',
        CASE WHEN null_receipt_id_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Transaction receipt IDs should not be null.'
    FROM transaction_shape

    UNION ALL

    SELECT
        'stg_etsy_transactions_orphan_receipt_count',
        CAST(orphan_transaction_count AS STRING),
        '0',
        CASE WHEN orphan_transaction_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Every staged transaction should join back to a staged receipt.'
    FROM transaction_receipt_integrity

    UNION ALL

    SELECT
        'stg_etsy_transactions_negative_quantity_or_money_count',
        CAST(
            negative_quantity_count
            + negative_item_price_count
            + negative_item_gross_amount_count
            AS STRING
        ),
        '0',
        CASE
            WHEN negative_quantity_count
                + negative_item_price_count
                + negative_item_gross_amount_count = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Transaction quantities and money fields should not be negative.'
    FROM transaction_shape

    UNION ALL

    SELECT
        'stg_etsy_payments_row_count',
        CAST(row_count AS STRING),
        '> 0',
        CASE WHEN row_count > 0 THEN 'PASS' ELSE 'FAIL' END,
        'Payment staging table should contain rows.'
    FROM payment_shape

    UNION ALL

    SELECT
        'stg_etsy_payments_duplicate_key_count',
        CAST(row_count - distinct_payment_count AS STRING),
        '0',
        CASE WHEN row_count - distinct_payment_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Payment staging table should have one row per payment_id.'
    FROM payment_shape

    UNION ALL

    SELECT
        'stg_etsy_payments_null_key_count',
        CAST(null_payment_id_count AS STRING),
        '0',
        CASE WHEN null_payment_id_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Payment IDs should not be null.'
    FROM payment_shape

    UNION ALL

    SELECT
        'stg_etsy_payments_null_receipt_id_count',
        CAST(null_receipt_id_count AS STRING),
        '0',
        CASE WHEN null_receipt_id_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Payment receipt IDs should not be null.'
    FROM payment_shape

    UNION ALL

    SELECT
        'stg_etsy_payments_orphan_receipt_count',
        CAST(orphan_payment_count AS STRING),
        '0',
        CASE WHEN orphan_payment_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Every staged payment should join back to a staged receipt.'
    FROM payment_receipt_integrity

    UNION ALL

    SELECT
        'stg_etsy_payments_null_selected_net_count',
        CAST(null_selected_net_count AS STRING),
        '0',
        CASE WHEN null_selected_net_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Every staged payment should have a selected net amount.'
    FROM payment_shape

    UNION ALL

    SELECT
        'stg_etsy_payment_receipt_coverage',
        CAST(receipts_without_payment_count AS STRING),
        'expected known skipped payment receipts',
        'INFO',
        'Receipts without payment rows are expected because some Etsy receipt payment endpoint calls returned 404s.'
    FROM receipt_payment_coverage
)

SELECT
    check_name,
    result_value,
    expected_value,
    check_status,
    notes
FROM validation_results
ORDER BY
    CASE check_status
        WHEN 'FAIL' THEN 1
        WHEN 'REVIEW' THEN 2
        WHEN 'INFO' THEN 3
        WHEN 'PASS' THEN 4
        ELSE 5
    END,
    check_name;