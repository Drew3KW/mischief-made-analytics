-- sql/analysis/dashboard_channel_daily.sql
-- Purpose:
-- Dashboard-facing daily channel KPI view for the Business Dashboard MVP.
--
-- Grain:
-- One row per order_date per channel.
--
-- Notes:
-- - Built from marts.fct_cross_channel_orders.
-- - Useful for Looker Studio charts that want channel as a dimension.
-- - Does not perform customer identity resolution.
-- - Does not perform product-family harmonization.

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_dashboard_channel_daily` AS

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
)

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

    SUM(CASE
        WHEN is_cancelled = FALSE THEN total_items
        ELSE 0
    END) AS total_units_sold,

    ROUND(SUM(CASE
        WHEN is_cancelled = FALSE THEN gross_amount
        ELSE 0
    END), 2) AS gross_revenue,

    ROUND(SUM(CASE
        WHEN is_cancelled = FALSE THEN refund_amount
        ELSE 0
    END), 2) AS refunded_amount,

    ROUND(SUM(CASE
        WHEN is_cancelled = FALSE THEN fee_amount
        ELSE 0
    END), 2) AS fee_amount,

    ROUND(SUM(CASE
        WHEN is_cancelled = FALSE THEN net_revenue_after_refunds
        ELSE 0
    END), 2) AS net_revenue_after_refunds,

    ROUND(SUM(CASE
        WHEN is_cancelled = FALSE THEN channel_reported_net_amount
        ELSE 0
    END), 2) AS channel_reported_net_amount,

    ROUND(
        SAFE_DIVIDE(
            SUM(CASE WHEN is_cancelled = FALSE THEN gross_amount ELSE 0 END),
            COUNT(DISTINCT CASE WHEN is_cancelled = FALSE THEN cross_channel_order_key END)
        ),
        2
    ) AS avg_order_value,

    ROUND(
        SAFE_DIVIDE(
            COUNT(DISTINCT CASE WHEN is_cancelled = TRUE THEN cross_channel_order_key END),
            COUNT(DISTINCT cross_channel_order_key)
        ),
        4
    ) AS cancellation_rate,

    ROUND(
        SAFE_DIVIDE(
            COUNT(DISTINCT CASE
                WHEN is_cancelled = FALSE
                    AND has_refund = TRUE
                THEN cross_channel_order_key
            END),
            COUNT(DISTINCT CASE WHEN is_cancelled = FALSE THEN cross_channel_order_key END)
        ),
        4
    ) AS refund_rate,

    ROUND(
        SAFE_DIVIDE(
            SUM(CASE WHEN is_cancelled = FALSE THEN total_items ELSE 0 END),
            COUNT(DISTINCT CASE WHEN is_cancelled = FALSE THEN cross_channel_order_key END)
        ),
        2
    ) AS avg_units_per_order

FROM order_base
GROUP BY
    order_date,
    channel
ORDER BY
    order_date,
    channel;