-- sql/analysis/cross_channel_revenue_daily.sql
-- Purpose:
-- Daily cross-channel revenue summary for Shopify and Etsy.
--
-- Grain:
-- One row per order_date and channel.
--
-- Notes:
-- - Built from marts.fct_cross_channel_orders.
-- - Uses channel-aware order keys.
-- - Keeps Shopify and Etsy separated by channel.
-- - Includes all-channel rollup rows using channel = 'all'.
-- - Does not perform customer identity resolution or product-family harmonization.

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_cross_channel_revenue_daily` AS

WITH order_base AS (
    SELECT
        channel,
        cross_channel_order_key,
        channel_customer_key,
        order_date,
        is_cancelled,
        has_refund,
        currency,
        gross_amount,
        refund_amount,
        fee_amount,
        net_revenue_after_refunds,
        channel_reported_net_amount,
        total_items,
        line_item_count,
        distinct_sku_count,
        source_edge_case_notes
    FROM `mischief-made-analytics.marts.fct_cross_channel_orders`
    WHERE order_date IS NOT NULL
),

channel_daily AS (
    SELECT
        order_date,
        channel,

        COUNT(DISTINCT cross_channel_order_key) AS submitted_orders,

        COUNT(DISTINCT CASE
            WHEN is_cancelled = FALSE THEN cross_channel_order_key
        END) AS completed_orders,

        COUNT(DISTINCT CASE
            WHEN is_cancelled = TRUE THEN cross_channel_order_key
        END) AS cancelled_orders,

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

        ROUND(
            SUM(CASE WHEN is_cancelled = FALSE THEN COALESCE(gross_amount, 0) ELSE 0 END),
            2
        ) AS gross_revenue,

        ROUND(
            SUM(CASE WHEN is_cancelled = FALSE THEN COALESCE(refund_amount, 0) ELSE 0 END),
            2
        ) AS refunded_amount,

        ROUND(
            SUM(CASE WHEN is_cancelled = FALSE THEN COALESCE(fee_amount, 0) ELSE 0 END),
            2
        ) AS fee_amount,

        ROUND(
            SUM(CASE WHEN is_cancelled = FALSE THEN COALESCE(net_revenue_after_refunds, 0) ELSE 0 END),
            2
        ) AS net_revenue_after_refunds,

        ROUND(
            SUM(CASE WHEN is_cancelled = FALSE THEN COALESCE(channel_reported_net_amount, 0) ELSE 0 END),
            2
        ) AS channel_reported_net_amount,

        SUM(CASE WHEN is_cancelled = FALSE THEN COALESCE(total_items, 0) ELSE 0 END) AS units_sold,

        SUM(CASE WHEN is_cancelled = FALSE THEN COALESCE(line_item_count, 0) ELSE 0 END) AS line_item_count,

        SUM(CASE WHEN is_cancelled = FALSE THEN COALESCE(distinct_sku_count, 0) ELSE 0 END) AS distinct_sku_count_sum

    FROM order_base
    GROUP BY
        order_date,
        channel
),

all_channel_daily AS (
    SELECT
        order_date,
        'all' AS channel,

        SUM(submitted_orders) AS submitted_orders,
        SUM(completed_orders) AS completed_orders,
        SUM(cancelled_orders) AS cancelled_orders,
        SUM(channel_scoped_customers) AS channel_scoped_customers,
        SUM(refunded_orders) AS refunded_orders,
        SUM(edge_case_orders) AS edge_case_orders,

        ROUND(SUM(gross_revenue), 2) AS gross_revenue,
        ROUND(SUM(refunded_amount), 2) AS refunded_amount,
        ROUND(SUM(fee_amount), 2) AS fee_amount,
        ROUND(SUM(net_revenue_after_refunds), 2) AS net_revenue_after_refunds,
        ROUND(SUM(channel_reported_net_amount), 2) AS channel_reported_net_amount,

        SUM(units_sold) AS units_sold,
        SUM(line_item_count) AS line_item_count,
        SUM(distinct_sku_count_sum) AS distinct_sku_count_sum

    FROM channel_daily
    GROUP BY order_date
),

combined AS (
    SELECT * FROM channel_daily

    UNION ALL

    SELECT * FROM all_channel_daily
)

SELECT
    order_date,
    channel,

    submitted_orders,
    completed_orders,
    cancelled_orders,
    channel_scoped_customers,
    refunded_orders,
    edge_case_orders,

    gross_revenue,
    refunded_amount,
    fee_amount,
    net_revenue_after_refunds,
    channel_reported_net_amount,

    units_sold,
    line_item_count,
    distinct_sku_count_sum,

    ROUND(SAFE_DIVIDE(gross_revenue, completed_orders), 2) AS avg_order_value,
    ROUND(SAFE_DIVIDE(cancelled_orders, submitted_orders), 4) AS cancellation_rate,
    ROUND(SAFE_DIVIDE(refunded_orders, completed_orders), 4) AS refund_rate,
    ROUND(SAFE_DIVIDE(units_sold, completed_orders), 2) AS avg_units_per_order,
    ROUND(SAFE_DIVIDE(gross_revenue, channel_scoped_customers), 2) AS revenue_per_channel_scoped_customer

FROM combined
ORDER BY
    order_date,
    CASE
        WHEN channel = 'all' THEN 1
        ELSE 0
    END,
    channel;