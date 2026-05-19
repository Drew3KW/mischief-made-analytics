-- sql/validation/cross_channel_revenue_validation.sql
-- Purpose:
-- Validate the first cross-channel Shopify plus Etsy revenue model.
--
-- Scope:
-- This validation checks row counts, keys, channel coverage, and summary consistency.
-- It does not validate final customer identity resolution, product-family harmonization,
-- or full accounting reconciliation.

WITH cross_channel_orders AS (
    SELECT *
    FROM `mischief-made-analytics.marts.fct_cross_channel_orders`
),

shopify_expected AS (
    SELECT
        COUNT(*) AS row_count
    FROM `mischief-made-analytics.marts.fct_orders`
    WHERE created_at_ts IS NOT NULL
      AND is_suspect_historical_timing = FALSE
),

etsy_expected AS (
    SELECT
        COUNT(*) AS row_count
    FROM `mischief-made-analytics.raw_load.etsy_receipts_api_latest`
    WHERE COALESCE(created_timestamp, create_timestamp) IS NOT NULL
),

order_counts AS (
    SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT cross_channel_order_key) AS distinct_order_key_count,
        COUNTIF(channel IS NULL OR TRIM(channel) = '') AS null_channel_count,
        COUNTIF(channel_order_id IS NULL OR TRIM(channel_order_id) = '') AS null_channel_order_id_count,
        COUNTIF(cross_channel_order_key IS NULL OR TRIM(cross_channel_order_key) = '') AS null_cross_channel_order_key_count,
        COUNTIF(order_date IS NULL) AS null_order_date_count,
        COUNTIF(gross_amount IS NULL) AS null_gross_amount_count,
        COUNTIF(net_revenue_after_refunds IS NULL) AS null_net_revenue_after_refunds_count
    FROM cross_channel_orders
),

channel_counts AS (
    SELECT
        channel,
        COUNT(*) AS row_count,
        ROUND(SUM(COALESCE(gross_amount, 0)), 2) AS gross_amount,
        ROUND(SUM(COALESCE(refund_amount, 0)), 2) AS refund_amount,
        ROUND(SUM(COALESCE(net_revenue_after_refunds, 0)), 2) AS net_revenue_after_refunds,
        ROUND(SUM(COALESCE(fee_amount, 0)), 2) AS fee_amount,
        COUNTIF(source_edge_case_notes IS NOT NULL) AS edge_case_order_count
    FROM cross_channel_orders
    GROUP BY channel
),

daily_long AS (
    SELECT *
    FROM `mischief-made-analytics.marts.anl_cross_channel_revenue_daily`
),

daily_pivot AS (
    SELECT *
    FROM `mischief-made-analytics.marts.anl_cross_channel_revenue_daily_pivot`
),

daily_channel_totals AS (
    SELECT
        order_date,
        SUM(submitted_orders) AS submitted_orders,
        SUM(completed_orders) AS completed_orders,
        ROUND(SUM(gross_revenue), 2) AS gross_revenue,
        ROUND(SUM(refunded_amount), 2) AS refunded_amount,
        ROUND(SUM(fee_amount), 2) AS fee_amount,
        ROUND(SUM(net_revenue_after_refunds), 2) AS net_revenue_after_refunds,
        SUM(edge_case_orders) AS edge_case_orders
    FROM daily_long
    WHERE channel IN ('shopify', 'etsy')
    GROUP BY order_date
),

daily_all_totals AS (
    SELECT
        order_date,
        submitted_orders,
        completed_orders,
        gross_revenue,
        refunded_amount,
        fee_amount,
        net_revenue_after_refunds,
        edge_case_orders
    FROM daily_long
    WHERE channel = 'all'
),

daily_long_mismatches AS (
    SELECT
        COUNT(*) AS compared_dates,
        COUNTIF(a.submitted_orders != c.submitted_orders) AS submitted_order_mismatches,
        COUNTIF(a.completed_orders != c.completed_orders) AS completed_order_mismatches,
        COUNTIF(a.gross_revenue != c.gross_revenue) AS gross_revenue_mismatches,
        COUNTIF(a.refunded_amount != c.refunded_amount) AS refunded_amount_mismatches,
        COUNTIF(a.fee_amount != c.fee_amount) AS fee_amount_mismatches,
        COUNTIF(a.net_revenue_after_refunds != c.net_revenue_after_refunds) AS net_revenue_mismatches,
        COUNTIF(a.edge_case_orders != c.edge_case_orders) AS edge_case_order_mismatches
    FROM daily_all_totals AS a
    INNER JOIN daily_channel_totals AS c
        ON a.order_date = c.order_date
),

pivot_vs_long AS (
    SELECT
        COUNT(*) AS compared_dates,

        COUNTIF(p.total_completed_orders != l.completed_orders) AS completed_order_mismatches,
        COUNTIF(p.total_gross_revenue != l.gross_revenue) AS gross_revenue_mismatches,
        COUNTIF(p.total_refunded_amount != l.refunded_amount) AS refunded_amount_mismatches,
        COUNTIF(p.total_net_revenue_after_refunds != l.net_revenue_after_refunds) AS net_revenue_mismatches,

        COUNTIF(p.shopify_completed_orders != COALESCE(s.completed_orders, 0)) AS shopify_completed_order_mismatches,
        COUNTIF(p.etsy_completed_orders != COALESCE(e.completed_orders, 0)) AS etsy_completed_order_mismatches,
        COUNTIF(p.shopify_gross_revenue != COALESCE(s.gross_revenue, 0)) AS shopify_gross_revenue_mismatches,
        COUNTIF(p.etsy_gross_revenue != COALESCE(e.gross_revenue, 0)) AS etsy_gross_revenue_mismatches

    FROM daily_pivot AS p
    INNER JOIN daily_long AS l
        ON p.order_date = l.order_date
       AND l.channel = 'all'
    LEFT JOIN daily_long AS s
        ON p.order_date = s.order_date
       AND s.channel = 'shopify'
    LEFT JOIN daily_long AS e
        ON p.order_date = e.order_date
       AND e.channel = 'etsy'
),

validation_results AS (
    SELECT
        'cross_channel_orders_row_count' AS check_name,
        CAST(row_count AS STRING) AS result_value,
        '> 0' AS expected_value,
        CASE WHEN row_count > 0 THEN 'PASS' ELSE 'FAIL' END AS check_status,
        'Cross-channel order mart should contain rows.' AS notes
    FROM order_counts

    UNION ALL

    SELECT
        'cross_channel_orders_duplicate_key_count',
        CAST(row_count - distinct_order_key_count AS STRING),
        '0',
        CASE WHEN row_count - distinct_order_key_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Each cross_channel_order_key should appear once.'
    FROM order_counts

    UNION ALL

    SELECT
        'cross_channel_orders_null_channel_count',
        CAST(null_channel_count AS STRING),
        '0',
        CASE WHEN null_channel_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Each cross-channel order should have a channel.'
    FROM order_counts

    UNION ALL

    SELECT
        'cross_channel_orders_null_channel_order_id_count',
        CAST(null_channel_order_id_count AS STRING),
        '0',
        CASE WHEN null_channel_order_id_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Each cross-channel order should have a channel order ID.'
    FROM order_counts

    UNION ALL

    SELECT
        'cross_channel_orders_null_cross_channel_order_key_count',
        CAST(null_cross_channel_order_key_count AS STRING),
        '0',
        CASE WHEN null_cross_channel_order_key_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Each cross-channel order should have a channel-aware order key.'
    FROM order_counts

    UNION ALL

    SELECT
        'cross_channel_orders_null_order_date_count',
        CAST(null_order_date_count AS STRING),
        '0',
        CASE WHEN null_order_date_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Each cross-channel order should have an order date.'
    FROM order_counts

    UNION ALL

    SELECT
        'cross_channel_orders_null_gross_amount_count',
        CAST(null_gross_amount_count AS STRING),
        '0',
        CASE WHEN null_gross_amount_count = 0 THEN 'PASS' ELSE 'REVIEW' END,
        'Gross amount should be populated for revenue modeling.'
    FROM order_counts

    UNION ALL

    SELECT
        'cross_channel_orders_null_net_revenue_after_refunds_count',
        CAST(null_net_revenue_after_refunds_count AS STRING),
        '0',
        CASE WHEN null_net_revenue_after_refunds_count = 0 THEN 'PASS' ELSE 'REVIEW' END,
        'Net revenue after refunds should be populated for revenue modeling.'
    FROM order_counts

    UNION ALL

    SELECT
        'cross_channel_orders_has_shopify',
        CAST(row_count AS STRING),
        '> 0',
        CASE WHEN row_count > 0 THEN 'PASS' ELSE 'FAIL' END,
        'Cross-channel order mart should include Shopify rows.'
    FROM channel_counts
    WHERE channel = 'shopify'

    UNION ALL

    SELECT
        'cross_channel_orders_has_etsy',
        CAST(row_count AS STRING),
        '> 0',
        CASE WHEN row_count > 0 THEN 'PASS' ELSE 'FAIL' END,
        'Cross-channel order mart should include Etsy rows.'
    FROM channel_counts
    WHERE channel = 'etsy'

    UNION ALL

    SELECT
        'shopify_order_count_matches_source',
        CAST((SELECT row_count FROM channel_counts WHERE channel = 'shopify') AS STRING),
        CAST((SELECT row_count FROM shopify_expected) AS STRING),
        CASE
            WHEN (SELECT row_count FROM channel_counts WHERE channel = 'shopify')
               = (SELECT row_count FROM shopify_expected)
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Shopify cross-channel row count should match trusted Shopify order fact count.'
    
    UNION ALL

    SELECT
        'etsy_order_count_matches_source',
        CAST((SELECT row_count FROM channel_counts WHERE channel = 'etsy') AS STRING),
        CAST((SELECT row_count FROM etsy_expected) AS STRING),
        CASE
            WHEN (SELECT row_count FROM channel_counts WHERE channel = 'etsy')
               = (SELECT row_count FROM etsy_expected)
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Etsy cross-channel row count should match Etsy receipt landing count.'

    UNION ALL

    SELECT
        'daily_long_all_vs_channel_submitted_orders',
        CAST(submitted_order_mismatches AS STRING),
        '0',
        CASE WHEN submitted_order_mismatches = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Daily all-channel submitted orders should equal Shopify plus Etsy submitted orders.'
    FROM daily_long_mismatches

    UNION ALL

    SELECT
        'daily_long_all_vs_channel_completed_orders',
        CAST(completed_order_mismatches AS STRING),
        '0',
        CASE WHEN completed_order_mismatches = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Daily all-channel completed orders should equal Shopify plus Etsy completed orders.'
    FROM daily_long_mismatches

    UNION ALL

    SELECT
        'daily_long_all_vs_channel_gross_revenue',
        CAST(gross_revenue_mismatches AS STRING),
        '0',
        CASE WHEN gross_revenue_mismatches = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Daily all-channel gross revenue should equal Shopify plus Etsy gross revenue.'
    FROM daily_long_mismatches

    UNION ALL

    SELECT
        'daily_long_all_vs_channel_refunded_amount',
        CAST(refunded_amount_mismatches AS STRING),
        '0',
        CASE WHEN refunded_amount_mismatches = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Daily all-channel refunded amount should equal Shopify plus Etsy refunded amount.'
    FROM daily_long_mismatches

    UNION ALL

    SELECT
        'daily_long_all_vs_channel_fee_amount',
        CAST(fee_amount_mismatches AS STRING),
        '0',
        CASE WHEN fee_amount_mismatches = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Daily all-channel fee amount should equal Shopify plus Etsy fee amount.'
    FROM daily_long_mismatches

    UNION ALL

    SELECT
        'daily_long_all_vs_channel_net_revenue',
        CAST(net_revenue_mismatches AS STRING),
        '0',
        CASE WHEN net_revenue_mismatches = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Daily all-channel net revenue should equal Shopify plus Etsy net revenue.'
    FROM daily_long_mismatches

    UNION ALL

    SELECT
        'daily_pivot_vs_long_completed_orders',
        CAST(completed_order_mismatches AS STRING),
        '0',
        CASE WHEN completed_order_mismatches = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Daily pivot completed orders should match long daily all-channel rows.'
    FROM pivot_vs_long

    UNION ALL

    SELECT
        'daily_pivot_vs_long_gross_revenue',
        CAST(gross_revenue_mismatches AS STRING),
        '0',
        CASE WHEN gross_revenue_mismatches = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Daily pivot gross revenue should match long daily all-channel rows.'
    FROM pivot_vs_long

    UNION ALL

    SELECT
        'daily_pivot_vs_long_net_revenue',
        CAST(net_revenue_mismatches AS STRING),
        '0',
        CASE WHEN net_revenue_mismatches = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Daily pivot net revenue should match long daily all-channel rows.'
    FROM pivot_vs_long

    UNION ALL

    SELECT
        'daily_pivot_shopify_channel_match',
        CAST(shopify_gross_revenue_mismatches AS STRING),
        '0',
        CASE WHEN shopify_gross_revenue_mismatches = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Daily pivot Shopify revenue should match long daily Shopify rows.'
    FROM pivot_vs_long

    UNION ALL

    SELECT
        'daily_pivot_etsy_channel_match',
        CAST(etsy_gross_revenue_mismatches AS STRING),
        '0',
        CASE WHEN etsy_gross_revenue_mismatches = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Daily pivot Etsy revenue should match long daily Etsy rows.'
    FROM pivot_vs_long

    UNION ALL

    SELECT
        'etsy_edge_case_orders',
        CAST(edge_case_order_count AS STRING),
        'Informational',
        'INFO',
        'Etsy edge case orders are retained in the model and flagged for downstream review.'
    FROM channel_counts
    WHERE channel = 'etsy'

    UNION ALL

    SELECT
        'cross_channel_order_summary',
        STRING_AGG(
            CONCAT(
                channel,
                '=',
                CAST(row_count AS STRING),
                ' orders, gross=',
                CAST(gross_amount AS STRING),
                ', net_after_refunds=',
                CAST(net_revenue_after_refunds AS STRING)
            ),
            '; '
            ORDER BY channel
        ),
        'Informational',
        'INFO',
        'Cross-channel order summary by channel.'
    FROM channel_counts
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