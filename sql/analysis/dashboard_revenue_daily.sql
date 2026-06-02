-- sql/analysis/dashboard_revenue_daily.sql
-- Purpose:
-- Dashboard-facing daily revenue and order KPI view for the Business Dashboard MVP.
--
-- Grain:
-- One row per order_date.
--
-- Notes:
-- - Built from marts.fct_cross_channel_orders.
-- - Uses channel-aware order keys.
-- - Does not perform customer identity resolution.
-- - Does not perform product-family harmonization.
-- - Etsy fee visibility depends on available receipt payment records.

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_dashboard_revenue_daily` AS

WITH order_base AS (
    SELECT
        channel,
        cross_channel_order_key,
        channel_customer_key,
        order_date,
        is_cancelled,
        has_refund,
        COALESCE(gross_amount, 0) AS gross_amount,
        COALESCE(refund_amount, 0) AS refund_amount,
        COALESCE(fee_amount, 0) AS fee_amount,
        COALESCE(net_revenue_after_refunds, 0) AS net_revenue_after_refunds,
        COALESCE(channel_reported_net_amount, 0) AS channel_reported_net_amount,
        COALESCE(total_items, 0) AS total_items,
        source_edge_case_notes
    FROM `mischief-made-analytics.marts.fct_cross_channel_orders`
    WHERE order_date IS NOT NULL
),

daily_rollup AS (
    SELECT
        order_date,

        COUNT(DISTINCT cross_channel_order_key) AS submitted_orders,

        COUNT(DISTINCT CASE
            WHEN is_cancelled = FALSE THEN cross_channel_order_key
        END) AS completed_orders,

        COUNT(DISTINCT CASE
            WHEN is_cancelled = TRUE THEN cross_channel_order_key
        END) AS cancelled_orders,

        COUNT(DISTINCT CASE
            WHEN channel = 'shopify'
                AND is_cancelled = FALSE
            THEN cross_channel_order_key
        END) AS shopify_completed_orders,

        COUNT(DISTINCT CASE
            WHEN channel = 'etsy'
                AND is_cancelled = FALSE
            THEN cross_channel_order_key
        END) AS etsy_completed_orders,

        COUNT(DISTINCT CASE
            WHEN is_cancelled = FALSE
                AND channel_customer_key IS NOT NULL
                AND TRIM(channel_customer_key) <> ''
            THEN CONCAT(channel, ':', channel_customer_key)
        END) AS channel_scoped_customers,

        COUNT(DISTINCT CASE
            WHEN is_cancelled = FALSE
                AND has_refund = TRUE
            THEN cross_channel_order_key
        END) AS refunded_orders,

        COUNT(DISTINCT CASE
            WHEN source_edge_case_notes IS NOT NULL
            THEN cross_channel_order_key
        END) AS edge_case_orders,

        COUNT(DISTINCT CASE
            WHEN channel = 'etsy'
                AND source_edge_case_notes = 'missing_etsy_payment_record'
            THEN cross_channel_order_key
        END) AS etsy_orders_missing_payment,

        ROUND(SUM(CASE
            WHEN is_cancelled = FALSE THEN gross_amount
            ELSE 0
        END), 2) AS total_gross_revenue,

        ROUND(SUM(CASE
            WHEN is_cancelled = FALSE THEN refund_amount
            ELSE 0
        END), 2) AS total_refunded_amount,

        ROUND(SUM(CASE
            WHEN is_cancelled = FALSE THEN fee_amount
            ELSE 0
        END), 2) AS total_fee_amount,

        ROUND(SUM(CASE
            WHEN is_cancelled = FALSE THEN net_revenue_after_refunds
            ELSE 0
        END), 2) AS total_net_revenue_after_refunds,

        ROUND(SUM(CASE
            WHEN is_cancelled = FALSE THEN channel_reported_net_amount
            ELSE 0
        END), 2) AS total_channel_reported_net_amount,

        ROUND(SUM(CASE
            WHEN channel = 'shopify'
                AND is_cancelled = FALSE
            THEN net_revenue_after_refunds
            ELSE 0
        END), 2) AS shopify_net_revenue_after_refunds,

        ROUND(SUM(CASE
            WHEN channel = 'etsy'
                AND is_cancelled = FALSE
            THEN net_revenue_after_refunds
            ELSE 0
        END), 2) AS etsy_net_revenue_after_refunds,

        ROUND(SUM(CASE
            WHEN channel = 'shopify'
                AND is_cancelled = FALSE
            THEN gross_amount
            ELSE 0
        END), 2) AS shopify_gross_revenue,

        ROUND(SUM(CASE
            WHEN channel = 'etsy'
                AND is_cancelled = FALSE
            THEN gross_amount
            ELSE 0
        END), 2) AS etsy_gross_revenue,

        SUM(CASE
            WHEN is_cancelled = FALSE THEN total_items
            ELSE 0
        END) AS total_units_sold

    FROM order_base
    GROUP BY order_date
)

SELECT
    order_date,
    submitted_orders,
    completed_orders,
    cancelled_orders,
    shopify_completed_orders,
    etsy_completed_orders,
    channel_scoped_customers,
    refunded_orders,
    edge_case_orders,
    etsy_orders_missing_payment,
    total_units_sold,
    total_gross_revenue,
    total_refunded_amount,
    total_fee_amount,
    total_net_revenue_after_refunds,
    total_channel_reported_net_amount,
    shopify_gross_revenue,
    etsy_gross_revenue,
    shopify_net_revenue_after_refunds,
    etsy_net_revenue_after_refunds,

    ROUND(SAFE_DIVIDE(total_gross_revenue, completed_orders), 2) AS avg_order_value,
    ROUND(SAFE_DIVIDE(cancelled_orders, submitted_orders), 4) AS cancellation_rate,
    ROUND(SAFE_DIVIDE(refunded_orders, completed_orders), 4) AS refund_rate,
    ROUND(SAFE_DIVIDE(total_units_sold, completed_orders), 2) AS avg_units_per_order,
    ROUND(SAFE_DIVIDE(total_gross_revenue, channel_scoped_customers), 2) AS revenue_per_channel_scoped_customer,

    ROUND(SAFE_DIVIDE(shopify_net_revenue_after_refunds, total_net_revenue_after_refunds), 4) AS shopify_net_revenue_share,
    ROUND(SAFE_DIVIDE(etsy_net_revenue_after_refunds, total_net_revenue_after_refunds), 4) AS etsy_net_revenue_share

FROM daily_rollup
ORDER BY order_date;