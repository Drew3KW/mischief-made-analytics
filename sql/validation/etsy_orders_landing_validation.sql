-- Etsy Orders Landing MVP validation
--
-- Purpose:
-- Validate the isolated Etsy API landing tables in raw_load.
--
-- Scope:
-- This validation checks landing-level completeness and key relationships only.
-- It does not validate final revenue logic, customer identity, or cross-channel models.

WITH receipt_counts AS (
    SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT receipt_id) AS distinct_receipt_count,
        COUNTIF(receipt_id IS NULL) AS null_receipt_id_count,
        COUNTIF(created_timestamp IS NULL AND create_timestamp IS NULL) AS null_created_timestamp_count,
        MIN(COALESCE(created_timestamp, create_timestamp)) AS min_receipt_timestamp,
        MAX(COALESCE(created_timestamp, create_timestamp)) AS max_receipt_timestamp
    FROM `mischief-made-analytics.raw_load.etsy_receipts_api_latest`
),

transaction_counts AS (
    SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT transaction_id) AS distinct_transaction_count,
        COUNTIF(transaction_id IS NULL) AS null_transaction_id_count,
        COUNTIF(receipt_id IS NULL) AS null_receipt_id_count,
        COUNTIF(sku IS NULL OR TRIM(sku) = '') AS blank_sku_count,
        COUNTIF(quantity IS NULL) AS null_quantity_count,
        COUNTIF(price IS NULL) AS null_price_count
    FROM `mischief-made-analytics.raw_load.etsy_receipt_transactions_api_latest`
),

payment_counts AS (
    SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT payment_id) AS distinct_payment_count,
        COUNTIF(payment_id IS NULL) AS null_payment_id_count,
        COUNTIF(receipt_id IS NULL) AS null_receipt_id_count,
        COUNTIF(amount_gross IS NULL) AS null_amount_gross_count,
        COUNTIF(amount_fees IS NULL) AS null_amount_fees_count,
        COUNTIF(amount_net IS NULL) AS null_amount_net_count
    FROM `mischief-made-analytics.raw_load.etsy_receipt_payments_api_latest`
),

transactions_missing_receipts AS (
    SELECT
        COUNT(*) AS row_count
    FROM `mischief-made-analytics.raw_load.etsy_receipt_transactions_api_latest` AS transactions
    LEFT JOIN `mischief-made-analytics.raw_load.etsy_receipts_api_latest` AS receipts
        ON transactions.receipt_id = receipts.receipt_id
    WHERE receipts.receipt_id IS NULL
),

payments_missing_receipts AS (
    SELECT
        COUNT(*) AS row_count
    FROM `mischief-made-analytics.raw_load.etsy_receipt_payments_api_latest` AS payments
    LEFT JOIN `mischief-made-analytics.raw_load.etsy_receipts_api_latest` AS receipts
        ON payments.receipt_id = receipts.receipt_id
    WHERE receipts.receipt_id IS NULL
),

receipts_missing_transactions AS (
    SELECT
        COUNT(*) AS row_count
    FROM `mischief-made-analytics.raw_load.etsy_receipts_api_latest` AS receipts
    LEFT JOIN `mischief-made-analytics.raw_load.etsy_receipt_transactions_api_latest` AS transactions
        ON receipts.receipt_id = transactions.receipt_id
    WHERE transactions.receipt_id IS NULL
),

receipts_missing_payments AS (
    SELECT
        COUNT(*) AS row_count
    FROM `mischief-made-analytics.raw_load.etsy_receipts_api_latest` AS receipts
    LEFT JOIN `mischief-made-analytics.raw_load.etsy_receipt_payments_api_latest` AS payments
        ON receipts.receipt_id = payments.receipt_id
    WHERE payments.receipt_id IS NULL
),

validation_results AS (
    SELECT
        'etsy_receipts_row_count' AS check_name,
        CAST(row_count AS STRING) AS result_value,
        '> 0' AS expected_value,
        CASE
            WHEN row_count > 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS check_status,
        'Receipts landing table should contain at least one row.' AS notes
    FROM receipt_counts

    UNION ALL

    SELECT
        'etsy_receipt_transactions_row_count' AS check_name,
        CAST(row_count AS STRING) AS result_value,
        '> 0' AS expected_value,
        CASE
            WHEN row_count > 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS check_status,
        'Receipt transactions landing table should contain at least one row.' AS notes
    FROM transaction_counts

    UNION ALL

    SELECT
        'etsy_receipt_payments_row_count' AS check_name,
        CAST(row_count AS STRING) AS result_value,
        '> 0' AS expected_value,
        CASE
            WHEN row_count > 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS check_status,
        'Receipt payments landing table should contain at least one row.' AS notes
    FROM payment_counts

    UNION ALL

    SELECT
        'etsy_receipts_duplicate_receipt_id' AS check_name,
        CAST(row_count - distinct_receipt_count AS STRING) AS result_value,
        '0' AS expected_value,
        CASE
            WHEN row_count - distinct_receipt_count = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS check_status,
        'Each receipt_id should appear once in the receipts landing table.' AS notes
    FROM receipt_counts

    UNION ALL

    SELECT
        'etsy_transactions_duplicate_transaction_id' AS check_name,
        CAST(row_count - distinct_transaction_count AS STRING) AS result_value,
        '0' AS expected_value,
        CASE
            WHEN row_count - distinct_transaction_count = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS check_status,
        'Each transaction_id should appear once in the receipt transactions landing table.' AS notes
    FROM transaction_counts

    UNION ALL

    SELECT
        'etsy_payments_duplicate_payment_id' AS check_name,
        CAST(row_count - distinct_payment_count AS STRING) AS result_value,
        '0' AS expected_value,
        CASE
            WHEN row_count - distinct_payment_count = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS check_status,
        'Each payment_id should appear once in the receipt payments landing table.' AS notes
    FROM payment_counts

    UNION ALL

    SELECT
        'etsy_receipts_null_receipt_id' AS check_name,
        CAST(null_receipt_id_count AS STRING) AS result_value,
        '0' AS expected_value,
        CASE
            WHEN null_receipt_id_count = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS check_status,
        'Receipts should always have receipt_id.' AS notes
    FROM receipt_counts

    UNION ALL

    SELECT
        'etsy_transactions_null_transaction_id' AS check_name,
        CAST(null_transaction_id_count AS STRING) AS result_value,
        '0' AS expected_value,
        CASE
            WHEN null_transaction_id_count = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS check_status,
        'Receipt transactions should always have transaction_id.' AS notes
    FROM transaction_counts

    UNION ALL

    SELECT
        'etsy_payments_null_payment_id' AS check_name,
        CAST(null_payment_id_count AS STRING) AS result_value,
        '0' AS expected_value,
        CASE
            WHEN null_payment_id_count = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS check_status,
        'Receipt payments should always have payment_id.' AS notes
    FROM payment_counts

    UNION ALL

    SELECT
        'etsy_transactions_null_receipt_id' AS check_name,
        CAST(null_receipt_id_count AS STRING) AS result_value,
        '0' AS expected_value,
        CASE
            WHEN null_receipt_id_count = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS check_status,
        'Receipt transactions should always link back to a receipt_id.' AS notes
    FROM transaction_counts

    UNION ALL

    SELECT
        'etsy_payments_null_receipt_id' AS check_name,
        CAST(null_receipt_id_count AS STRING) AS result_value,
        '0' AS expected_value,
        CASE
            WHEN null_receipt_id_count = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS check_status,
        'Receipt payments should always link back to a receipt_id.' AS notes
    FROM payment_counts

    UNION ALL

    SELECT
        'etsy_transactions_missing_parent_receipt' AS check_name,
        CAST(row_count AS STRING) AS result_value,
        '0' AS expected_value,
        CASE
            WHEN row_count = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS check_status,
        'Every transaction receipt_id should exist in the receipts landing table.' AS notes
    FROM transactions_missing_receipts

    UNION ALL

    SELECT
        'etsy_payments_missing_parent_receipt' AS check_name,
        CAST(row_count AS STRING) AS result_value,
        '0' AS expected_value,
        CASE
            WHEN row_count = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS check_status,
        'Every payment receipt_id should exist in the receipts landing table.' AS notes
    FROM payments_missing_receipts

    UNION ALL

    SELECT
        'etsy_receipts_missing_transactions' AS check_name,
        CAST(row_count AS STRING) AS result_value,
        '0' AS expected_value,
        CASE
            WHEN row_count = 0 THEN 'PASS'
            ELSE 'REVIEW'
        END AS check_status,
        'Most receipts should have transactions, but this is REVIEW rather than FAIL until more Etsy edge cases are understood.' AS notes
    FROM receipts_missing_transactions

    UNION ALL

    SELECT
        'etsy_receipts_missing_payments' AS check_name,
        CAST(row_count AS STRING) AS result_value,
        '0' AS expected_value,
        CASE
            WHEN row_count = 0 THEN 'PASS'
            ELSE 'REVIEW'
        END AS check_status,
        'Some receipt payment fetches returned Etsy 404 responses during extraction, so missing payments are REVIEW for now.' AS notes
    FROM receipts_missing_payments

    UNION ALL

    SELECT
        'etsy_transactions_blank_sku' AS check_name,
        CAST(blank_sku_count AS STRING) AS result_value,
        '0 preferred' AS expected_value,
        CASE
            WHEN blank_sku_count = 0 THEN 'PASS'
            ELSE 'REVIEW'
        END AS check_status,
        'Blank SKUs affect future product mapping, but are not a landing failure.' AS notes
    FROM transaction_counts

    UNION ALL

    SELECT
        'etsy_transactions_null_quantity' AS check_name,
        CAST(null_quantity_count AS STRING) AS result_value,
        '0' AS expected_value,
        CASE
            WHEN null_quantity_count = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS check_status,
        'Receipt transactions should have quantity for future order-item modeling.' AS notes
    FROM transaction_counts

    UNION ALL

    SELECT
        'etsy_transactions_null_price' AS check_name,
        CAST(null_price_count AS STRING) AS result_value,
        '0' AS expected_value,
        CASE
            WHEN null_price_count = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS check_status,
        'Receipt transactions should have price for future order-item revenue modeling.' AS notes
    FROM transaction_counts

    UNION ALL

    SELECT
        'etsy_payments_null_amount_gross' AS check_name,
        CAST(null_amount_gross_count AS STRING) AS result_value,
        '0' AS expected_value,
        CASE
            WHEN null_amount_gross_count = 0 THEN 'PASS'
            ELSE 'REVIEW'
        END AS check_status,
        'Payment gross amount is needed for future financial reconciliation.' AS notes
    FROM payment_counts

    UNION ALL

    SELECT
        'etsy_payments_null_amount_fees' AS check_name,
        CAST(null_amount_fees_count AS STRING) AS result_value,
        '0' AS expected_value,
        CASE
            WHEN null_amount_fees_count = 0 THEN 'PASS'
            ELSE 'REVIEW'
        END AS check_status,
        'Payment fee amount is needed for future fee and net revenue modeling.' AS notes
    FROM payment_counts

    UNION ALL

    SELECT
        'etsy_payments_null_amount_net' AS check_name,
        CAST(null_amount_net_count AS STRING) AS result_value,
        '0' AS expected_value,
        CASE
            WHEN null_amount_net_count = 0 THEN 'PASS'
            ELSE 'REVIEW'
        END AS check_status,
        'Payment net amount is needed for future net revenue modeling.' AS notes
    FROM payment_counts

    UNION ALL

    SELECT
        'etsy_receipts_timestamp_range' AS check_name,
        CONCAT(
            CAST(TIMESTAMP_SECONDS(min_receipt_timestamp) AS STRING),
            ' to ',
            CAST(TIMESTAMP_SECONDS(max_receipt_timestamp) AS STRING)
        ) AS result_value,
        'Recent receipt timestamp range' AS expected_value,
        'INFO' AS check_status,
        'Informational timestamp range for the current Etsy receipt landing.' AS notes
    FROM receipt_counts

    UNION ALL

    SELECT
        'etsy_landing_row_summary' AS check_name,
        CONCAT(
            'receipts=',
            CAST((SELECT row_count FROM receipt_counts) AS STRING),
            ', transactions=',
            CAST((SELECT row_count FROM transaction_counts) AS STRING),
            ', payments=',
            CAST((SELECT row_count FROM payment_counts) AS STRING)
        ) AS result_value,
        'Informational' AS expected_value,
        'INFO' AS check_status,
        'Summary of current Etsy landing table row counts.' AS notes
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