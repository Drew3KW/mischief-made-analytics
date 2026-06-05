-- sql/validation/etsy_marts_validation.sql
-- Purpose:
-- Validate Etsy mart models for Milestone 49.
--
-- Scope:
-- - marts.fct_etsy_orders
-- - marts.fct_etsy_order_items
-- - marts.fct_etsy_payments
--
-- Notes:
-- - Etsy payment rows are expected to be fewer than Etsy order rows because
--   some receipt payment endpoint calls returned 404s during payment enrichment.
-- - This validation checks mart shape, uniqueness, staging-to-mart counts,
--   basic referential integrity, and rollups from order items/payments to orders.

WITH stg_receipts AS (
    SELECT *
    FROM `mischief-made-analytics.staging.stg_etsy_receipts`
),

stg_transactions AS (
    SELECT *
    FROM `mischief-made-analytics.staging.stg_etsy_receipt_transactions`
),

stg_payments AS (
    SELECT *
    FROM `mischief-made-analytics.staging.stg_etsy_receipt_payments`
),

orders AS (
    SELECT *
    FROM `mischief-made-analytics.marts.fct_etsy_orders`
),

order_items AS (
    SELECT *
    FROM `mischief-made-analytics.marts.fct_etsy_order_items`
),

payments AS (
    SELECT *
    FROM `mischief-made-analytics.marts.fct_etsy_payments`
),

staging_counts AS (
    SELECT
        (SELECT COUNT(*) FROM stg_receipts) AS stg_receipt_count,
        (SELECT COUNT(*) FROM stg_transactions) AS stg_transaction_count,
        (SELECT COUNT(*) FROM stg_payments) AS stg_payment_count
),

order_shape AS (
    SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT receipt_id) AS distinct_receipt_count,
        COUNTIF(receipt_id IS NULL) AS null_receipt_id_count,
        COUNTIF(etsy_order_key IS NULL OR TRIM(etsy_order_key) = '') AS null_etsy_order_key_count,
        COUNTIF(cross_channel_order_key IS NULL OR TRIM(cross_channel_order_key) = '') AS null_cross_channel_order_key_count,
        COUNTIF(order_date IS NULL) AS null_order_date_count,
        MIN(order_date) AS min_order_date,
        MAX(order_date) AS max_order_date,
        COUNTIF(receipt_gross_amount < 0) AS negative_receipt_gross_count,
        COUNTIF(order_item_count < 0) AS negative_order_item_count,
        COUNTIF(total_items < 0) AS negative_total_items_count,
        COUNTIF(payment_count < 0) AS negative_payment_count
    FROM orders
),

order_item_shape AS (
    SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT transaction_id) AS distinct_transaction_count,
        COUNTIF(transaction_id IS NULL) AS null_transaction_id_count,
        COUNTIF(receipt_id IS NULL) AS null_receipt_id_count,
        COUNTIF(etsy_order_item_key IS NULL OR TRIM(etsy_order_item_key) = '') AS null_etsy_order_item_key_count,
        COUNTIF(cross_channel_order_item_key IS NULL OR TRIM(cross_channel_order_item_key) = '') AS null_cross_channel_order_item_key_count,
        COUNTIF(cross_channel_order_key IS NULL OR TRIM(cross_channel_order_key) = '') AS null_cross_channel_order_key_count,
        COUNTIF(order_date IS NULL) AS null_order_date_count,
        MIN(order_date) AS min_order_date,
        MAX(order_date) AS max_order_date,
        COUNTIF(quantity < 0) AS negative_quantity_count,
        COUNTIF(item_price < 0) AS negative_item_price_count,
        COUNTIF(item_gross_amount < 0) AS negative_item_gross_amount_count,
        COUNTIF(has_blank_sku) AS blank_sku_item_count
    FROM order_items
),

payment_shape AS (
    SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT payment_id) AS distinct_payment_count,
        COUNTIF(payment_id IS NULL) AS null_payment_id_count,
        COUNTIF(receipt_id IS NULL) AS null_receipt_id_count,
        COUNTIF(etsy_payment_key IS NULL OR TRIM(etsy_payment_key) = '') AS null_etsy_payment_key_count,
        COUNTIF(cross_channel_payment_key IS NULL OR TRIM(cross_channel_payment_key) = '') AS null_cross_channel_payment_key_count,
        COUNTIF(cross_channel_order_key IS NULL OR TRIM(cross_channel_order_key) = '') AS null_cross_channel_order_key_count,
        COUNTIF(order_date IS NULL) AS null_order_date_count,
        MIN(order_date) AS min_order_date,
        MAX(order_date) AS max_order_date,
        COUNTIF(selected_gross_amount < 0) AS negative_selected_gross_count,
        COUNTIF(selected_fee_amount < 0) AS negative_selected_fee_count,
        COUNTIF(selected_net_amount IS NULL) AS null_selected_net_count
    FROM payments
),

order_item_integrity AS (
    SELECT
        COUNT(*) AS orphan_order_item_count
    FROM order_items AS oi
    LEFT JOIN orders AS o
        ON oi.receipt_id = o.receipt_id
    WHERE o.receipt_id IS NULL
),

payment_integrity AS (
    SELECT
        COUNT(*) AS orphan_payment_count
    FROM payments AS p
    LEFT JOIN orders AS o
        ON p.receipt_id = o.receipt_id
    WHERE o.receipt_id IS NULL
),

order_item_rollup AS (
    SELECT
        receipt_id,
        COUNT(DISTINCT transaction_id) AS order_item_count,
        SUM(COALESCE(quantity, 0)) AS total_items,
        ROUND(SUM(COALESCE(item_gross_amount, 0)), 2) AS order_item_gross_amount,
        COUNTIF(has_blank_sku) AS blank_sku_item_count
    FROM order_items
    GROUP BY receipt_id
),

order_item_rollup_vs_orders AS (
    SELECT
        COUNT(*) AS compared_order_count,

        COUNTIF(
            COALESCE(o.order_item_count, -1)
                != COALESCE(oi.order_item_count, -2)
        ) AS order_item_count_mismatches,

        COUNTIF(
            COALESCE(o.total_items, -1)
                != COALESCE(oi.total_items, -2)
        ) AS total_items_mismatches,

        COUNTIF(
            COALESCE(ROUND(o.order_item_gross_amount, 2), -1)
                != COALESCE(oi.order_item_gross_amount, -2)
        ) AS order_item_gross_amount_mismatches,

        COUNTIF(
            COALESCE(o.blank_sku_item_count, -1)
                != COALESCE(oi.blank_sku_item_count, -2)
        ) AS blank_sku_item_count_mismatches

    FROM orders AS o
    LEFT JOIN order_item_rollup AS oi
        ON o.receipt_id = oi.receipt_id
),

payment_rollup AS (
    SELECT
        receipt_id,
        COUNT(DISTINCT payment_id) AS payment_count,
        ROUND(SUM(COALESCE(selected_gross_amount, 0)), 2) AS payment_gross_amount,
        ROUND(SUM(COALESCE(selected_fee_amount, 0)), 2) AS payment_fee_amount,
        ROUND(SUM(COALESCE(selected_net_amount, 0)), 2) AS payment_net_amount
    FROM payments
    GROUP BY receipt_id
),

payment_rollup_vs_orders AS (
    SELECT
        COUNT(*) AS compared_order_count,

        COUNTIF(
            COALESCE(o.payment_count, -1)
                != COALESCE(p.payment_count, 0)
        ) AS payment_count_mismatches,

        COUNTIF(
            COALESCE(ROUND(o.payment_gross_amount, 2), -1)
                != COALESCE(p.payment_gross_amount, 0)
        ) AS payment_gross_amount_mismatches,

        COUNTIF(
            COALESCE(ROUND(o.payment_fee_amount, 2), -1)
                != COALESCE(p.payment_fee_amount, 0)
        ) AS payment_fee_amount_mismatches,

        COUNTIF(
            COALESCE(ROUND(o.payment_net_amount, 2), -1)
                != COALESCE(p.payment_net_amount, 0)
        ) AS payment_net_amount_mismatches

    FROM orders AS o
    LEFT JOIN payment_rollup AS p
        ON o.receipt_id = p.receipt_id
),

payment_coverage AS (
    SELECT
        COUNT(DISTINCT o.receipt_id) AS order_count,
        COUNT(DISTINCT p.receipt_id) AS orders_with_payment_count,
        COUNT(DISTINCT o.receipt_id) - COUNT(DISTINCT p.receipt_id) AS orders_without_payment_count,
        COUNTIF(o.missing_payment_record) AS missing_payment_flag_count
    FROM orders AS o
    LEFT JOIN payments AS p
        ON o.receipt_id = p.receipt_id
),

validation_results AS (
    SELECT
        'fct_etsy_orders_row_count' AS check_name,
        CAST(row_count AS STRING) AS result_value,
        '> 0' AS expected_value,
        CASE WHEN row_count > 0 THEN 'PASS' ELSE 'FAIL' END AS check_status,
        'Etsy order fact should contain rows.' AS notes
    FROM order_shape

    UNION ALL

    SELECT
        'fct_etsy_orders_matches_staging_receipts',
        CAST(o.row_count - s.stg_receipt_count AS STRING),
        '0',
        CASE WHEN o.row_count = s.stg_receipt_count THEN 'PASS' ELSE 'FAIL' END,
        'Etsy order fact row count should match staged receipts.'
    FROM order_shape AS o
    CROSS JOIN staging_counts AS s

    UNION ALL

    SELECT
        'fct_etsy_orders_duplicate_key_count',
        CAST(row_count - distinct_receipt_count AS STRING),
        '0',
        CASE WHEN row_count - distinct_receipt_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Etsy order fact should have one row per receipt_id.'
    FROM order_shape

    UNION ALL

    SELECT
        'fct_etsy_orders_null_key_count',
        CAST(null_receipt_id_count + null_etsy_order_key_count + null_cross_channel_order_key_count AS STRING),
        '0',
        CASE
            WHEN null_receipt_id_count + null_etsy_order_key_count + null_cross_channel_order_key_count = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Etsy order keys should not be null.'
    FROM order_shape

    UNION ALL

    SELECT
        'fct_etsy_orders_null_order_date_count',
        CAST(null_order_date_count AS STRING),
        '0',
        CASE WHEN null_order_date_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Etsy orders should have an order_date.'
    FROM order_shape

    UNION ALL

    SELECT
        'fct_etsy_orders_date_range',
        CONCAT(CAST(min_order_date AS STRING), ' to ', CAST(max_order_date AS STRING)),
        'populated date range',
        CASE
            WHEN min_order_date IS NOT NULL AND max_order_date IS NOT NULL
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Etsy order fact should have a populated date range.'
    FROM order_shape

    UNION ALL

    SELECT
        'fct_etsy_orders_negative_count',
        CAST(
            negative_receipt_gross_count
            + negative_order_item_count
            + negative_total_items_count
            + negative_payment_count
            AS STRING
        ),
        '0',
        CASE
            WHEN negative_receipt_gross_count
                + negative_order_item_count
                + negative_total_items_count
                + negative_payment_count = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Etsy order fact count and money fields should not be negative.'
    FROM order_shape

    UNION ALL

    SELECT
        'fct_etsy_order_items_row_count',
        CAST(row_count AS STRING),
        '> 0',
        CASE WHEN row_count > 0 THEN 'PASS' ELSE 'FAIL' END,
        'Etsy order item fact should contain rows.'
    FROM order_item_shape

    UNION ALL

    SELECT
        'fct_etsy_order_items_matches_staging_transactions',
        CAST(oi.row_count - s.stg_transaction_count AS STRING),
        '0',
        CASE WHEN oi.row_count = s.stg_transaction_count THEN 'PASS' ELSE 'FAIL' END,
        'Etsy order item fact row count should match staged transactions.'
    FROM order_item_shape AS oi
    CROSS JOIN staging_counts AS s

    UNION ALL

    SELECT
        'fct_etsy_order_items_duplicate_key_count',
        CAST(row_count - distinct_transaction_count AS STRING),
        '0',
        CASE WHEN row_count - distinct_transaction_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Etsy order item fact should have one row per transaction_id.'
    FROM order_item_shape

    UNION ALL

    SELECT
        'fct_etsy_order_items_null_key_count',
        CAST(
            null_transaction_id_count
            + null_etsy_order_item_key_count
            + null_cross_channel_order_item_key_count
            + null_cross_channel_order_key_count
            AS STRING
        ),
        '0',
        CASE
            WHEN null_transaction_id_count
                + null_etsy_order_item_key_count
                + null_cross_channel_order_item_key_count
                + null_cross_channel_order_key_count = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Etsy order item keys should not be null.'
    FROM order_item_shape

    UNION ALL

    SELECT
        'fct_etsy_order_items_null_order_date_count',
        CAST(null_order_date_count AS STRING),
        '0',
        CASE WHEN null_order_date_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Etsy order items should have an order_date.'
    FROM order_item_shape

    UNION ALL

    SELECT
        'fct_etsy_order_items_orphan_order_count',
        CAST(orphan_order_item_count AS STRING),
        '0',
        CASE WHEN orphan_order_item_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Every Etsy order item should join back to fct_etsy_orders.'
    FROM order_item_integrity

    UNION ALL

    SELECT
        'fct_etsy_order_items_negative_count',
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
        'Etsy order item quantities and money fields should not be negative.'
    FROM order_item_shape

    UNION ALL

    SELECT
        'fct_etsy_order_items_blank_sku_count',
        CAST(blank_sku_item_count AS STRING),
        'informational',
        'INFO',
        'Blank Etsy SKUs are expected for some transaction rows.'
    FROM order_item_shape

    UNION ALL

    SELECT
        'fct_etsy_payments_row_count',
        CAST(row_count AS STRING),
        '> 0',
        CASE WHEN row_count > 0 THEN 'PASS' ELSE 'FAIL' END,
        'Etsy payment fact should contain rows.'
    FROM payment_shape

    UNION ALL

    SELECT
        'fct_etsy_payments_matches_staging_payments',
        CAST(p.row_count - s.stg_payment_count AS STRING),
        '0',
        CASE WHEN p.row_count = s.stg_payment_count THEN 'PASS' ELSE 'FAIL' END,
        'Etsy payment fact row count should match staged payments.'
    FROM payment_shape AS p
    CROSS JOIN staging_counts AS s

    UNION ALL

    SELECT
        'fct_etsy_payments_duplicate_key_count',
        CAST(row_count - distinct_payment_count AS STRING),
        '0',
        CASE WHEN row_count - distinct_payment_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Etsy payment fact should have one row per payment_id.'
    FROM payment_shape

    UNION ALL

    SELECT
        'fct_etsy_payments_null_key_count',
        CAST(
            null_payment_id_count
            + null_etsy_payment_key_count
            + null_cross_channel_payment_key_count
            + null_cross_channel_order_key_count
            AS STRING
        ),
        '0',
        CASE
            WHEN null_payment_id_count
                + null_etsy_payment_key_count
                + null_cross_channel_payment_key_count
                + null_cross_channel_order_key_count = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Etsy payment keys should not be null.'
    FROM payment_shape

    UNION ALL

    SELECT
        'fct_etsy_payments_null_order_date_count',
        CAST(null_order_date_count AS STRING),
        '0',
        CASE WHEN null_order_date_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Etsy payments should have an order_date.'
    FROM payment_shape

    UNION ALL

    SELECT
        'fct_etsy_payments_orphan_order_count',
        CAST(orphan_payment_count AS STRING),
        '0',
        CASE WHEN orphan_payment_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Every Etsy payment should join back to fct_etsy_orders.'
    FROM payment_integrity

    UNION ALL

    SELECT
        'fct_etsy_payments_null_selected_net_count',
        CAST(null_selected_net_count AS STRING),
        '0',
        CASE WHEN null_selected_net_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Every Etsy payment should have a selected net amount.'
    FROM payment_shape

    UNION ALL

    SELECT
        'fct_etsy_order_item_rollup_vs_orders',
        CAST(
            order_item_count_mismatches
            + total_items_mismatches
            + order_item_gross_amount_mismatches
            + blank_sku_item_count_mismatches
            AS STRING
        ),
        '0',
        CASE
            WHEN order_item_count_mismatches
                + total_items_mismatches
                + order_item_gross_amount_mismatches
                + blank_sku_item_count_mismatches = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Order item rollups should tie to fct_etsy_orders.'
    FROM order_item_rollup_vs_orders

    UNION ALL

    SELECT
        'fct_etsy_payment_rollup_vs_orders',
        CAST(
            payment_count_mismatches
            + payment_gross_amount_mismatches
            + payment_fee_amount_mismatches
            + payment_net_amount_mismatches
            AS STRING
        ),
        '0',
        CASE
            WHEN payment_count_mismatches
                + payment_gross_amount_mismatches
                + payment_fee_amount_mismatches
                + payment_net_amount_mismatches = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Payment rollups should tie to fct_etsy_orders.'
    FROM payment_rollup_vs_orders

    UNION ALL

    SELECT
        'fct_etsy_payment_coverage',
        CAST(orders_without_payment_count AS STRING),
        'expected known skipped payment receipts',
        'INFO',
        'Orders without payment rows are expected because some Etsy receipt payment endpoint calls returned 404s.'
    FROM payment_coverage

    UNION ALL

    SELECT
        'fct_etsy_missing_payment_flag_alignment',
        CAST(orders_without_payment_count - missing_payment_flag_count AS STRING),
        '0',
        CASE
            WHEN orders_without_payment_count = missing_payment_flag_count
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'missing_payment_record flag should align with orders without payment rows.'
    FROM payment_coverage
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