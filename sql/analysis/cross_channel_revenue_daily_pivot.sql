-- sql/analysis/cross_channel_revenue_daily_pivot.sql
-- Purpose:
-- Side-by-side daily Shopify and Etsy revenue summary.
--
-- Grain:
-- One row per order_date.
--
-- Notes:
-- - Built from marts.fct_cross_channel_orders.
-- - Focuses on dates where Etsy landing data exists.
-- - Shows Shopify, Etsy, and combined daily order/revenue metrics side by side.
-- - Uses channel-aware order keys.
-- - Does not perform customer identity resolution or product-family harmonization.

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_cross_channel_revenue_daily_pivot` AS

WITH order_base AS (
    SELECT
        channel,
        cross_channel_order_key,
        order_date,
        is_cancelled,
        has_refund,
        gross_amount,
        refund_amount,
        fee_amount,
        net_revenue_after_refunds,
        channel_reported_net_amount,
        total_items,
        source_edge_case_notes
    FROM `mischief-made-analytics.marts.fct_cross_channel_orders`
    WHERE order_date IS NOT NULL
),

etsy_date_range AS (
    SELECT
        MIN(order_date) AS min_etsy_order_date,
        MAX(order_date) AS max_etsy_order_date
    FROM order_base
    WHERE channel = 'etsy'
),

daily_pivot AS (
    SELECT
        ob.order_date,

        COUNT(DISTINCT CASE
            WHEN ob.channel = 'shopify'
            THEN ob.cross_channel_order_key
        END) AS shopify_submitted_orders,

        COUNT(DISTINCT CASE
            WHEN ob.channel = 'shopify'
             AND ob.is_cancelled = FALSE
            THEN ob.cross_channel_order_key
        END) AS shopify_completed_orders,

        COUNT(DISTINCT CASE
            WHEN ob.channel = 'etsy'
            THEN ob.cross_channel_order_key
        END) AS etsy_submitted_orders,

        COUNT(DISTINCT CASE
            WHEN ob.channel = 'etsy'
             AND ob.is_cancelled = FALSE
            THEN ob.cross_channel_order_key
        END) AS etsy_completed_orders,

        COUNT(DISTINCT CASE
            WHEN ob.is_cancelled = FALSE
            THEN ob.cross_channel_order_key
        END) AS total_completed_orders,

        ROUND(SUM(CASE
            WHEN ob.channel = 'shopify'
             AND ob.is_cancelled = FALSE
            THEN COALESCE(ob.gross_amount, 0)
            ELSE 0
        END), 2) AS shopify_gross_revenue,

        ROUND(SUM(CASE
            WHEN ob.channel = 'etsy'
             AND ob.is_cancelled = FALSE
            THEN COALESCE(ob.gross_amount, 0)
            ELSE 0
        END), 2) AS etsy_gross_revenue,

        ROUND(SUM(CASE
            WHEN ob.is_cancelled = FALSE
            THEN COALESCE(ob.gross_amount, 0)
            ELSE 0
        END), 2) AS total_gross_revenue,

        ROUND(SUM(CASE
            WHEN ob.channel = 'shopify'
             AND ob.is_cancelled = FALSE
            THEN COALESCE(ob.refund_amount, 0)
            ELSE 0
        END), 2) AS shopify_refunded_amount,

        ROUND(SUM(CASE
            WHEN ob.channel = 'etsy'
             AND ob.is_cancelled = FALSE
            THEN COALESCE(ob.refund_amount, 0)
            ELSE 0
        END), 2) AS etsy_refunded_amount,

        ROUND(SUM(CASE
            WHEN ob.is_cancelled = FALSE
            THEN COALESCE(ob.refund_amount, 0)
            ELSE 0
        END), 2) AS total_refunded_amount,

        ROUND(SUM(CASE
            WHEN ob.channel = 'etsy'
             AND ob.is_cancelled = FALSE
            THEN COALESCE(ob.fee_amount, 0)
            ELSE 0
        END), 2) AS etsy_fee_amount,

        ROUND(SUM(CASE
            WHEN ob.channel = 'shopify'
             AND ob.is_cancelled = FALSE
            THEN COALESCE(ob.net_revenue_after_refunds, 0)
            ELSE 0
        END), 2) AS shopify_net_revenue_after_refunds,

        ROUND(SUM(CASE
            WHEN ob.channel = 'etsy'
             AND ob.is_cancelled = FALSE
            THEN COALESCE(ob.net_revenue_after_refunds, 0)
            ELSE 0
        END), 2) AS etsy_net_revenue_after_refunds,

        ROUND(SUM(CASE
            WHEN ob.is_cancelled = FALSE
            THEN COALESCE(ob.net_revenue_after_refunds, 0)
            ELSE 0
        END), 2) AS total_net_revenue_after_refunds,

        ROUND(SUM(CASE
            WHEN ob.channel = 'etsy'
             AND ob.is_cancelled = FALSE
            THEN COALESCE(ob.channel_reported_net_amount, 0)
            ELSE 0
        END), 2) AS etsy_channel_reported_net_amount,

        SUM(CASE
            WHEN ob.channel = 'shopify'
             AND ob.is_cancelled = FALSE
            THEN COALESCE(ob.total_items, 0)
            ELSE 0
        END) AS shopify_units_sold,

        SUM(CASE
            WHEN ob.channel = 'etsy'
             AND ob.is_cancelled = FALSE
            THEN COALESCE(ob.total_items, 0)
            ELSE 0
        END) AS etsy_units_sold,

        SUM(CASE
            WHEN ob.is_cancelled = FALSE
            THEN COALESCE(ob.total_items, 0)
            ELSE 0
        END) AS total_units_sold,

        COUNT(DISTINCT CASE
            WHEN ob.channel = 'etsy'
             AND ob.source_edge_case_notes IS NOT NULL
            THEN ob.cross_channel_order_key
        END) AS etsy_edge_case_orders

    FROM order_base AS ob
    CROSS JOIN etsy_date_range AS edr
    WHERE ob.order_date BETWEEN edr.min_etsy_order_date AND edr.max_etsy_order_date
    GROUP BY ob.order_date
)

SELECT
    order_date,

    shopify_submitted_orders,
    shopify_completed_orders,
    shopify_gross_revenue,
    shopify_refunded_amount,
    shopify_net_revenue_after_refunds,
    shopify_units_sold,

    etsy_submitted_orders,
    etsy_completed_orders,
    etsy_gross_revenue,
    etsy_refunded_amount,
    etsy_fee_amount,
    etsy_net_revenue_after_refunds,
    etsy_channel_reported_net_amount,
    etsy_units_sold,
    etsy_edge_case_orders,

    total_completed_orders,
    total_gross_revenue,
    total_refunded_amount,
    total_net_revenue_after_refunds,
    total_units_sold,

    ROUND(SAFE_DIVIDE(etsy_gross_revenue, total_gross_revenue), 4) AS etsy_gross_revenue_share,
    ROUND(SAFE_DIVIDE(shopify_gross_revenue, total_gross_revenue), 4) AS shopify_gross_revenue_share,
    ROUND(SAFE_DIVIDE(total_gross_revenue, total_completed_orders), 2) AS total_avg_order_value

FROM daily_pivot
ORDER BY order_date;