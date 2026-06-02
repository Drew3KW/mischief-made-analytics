-- sql/analysis/dashboard_revenue_monthly.sql
-- Purpose:
-- Dashboard-facing monthly revenue and order KPI view for the Business Dashboard MVP.
--
-- Grain:
-- One row per order_month.
--
-- Notes:
-- - Built from marts.anl_dashboard_revenue_daily.
-- - Keeps Shopify and Etsy revenue split visible.
-- - Includes month-over-month KPI movement for dashboard trend cards.

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_dashboard_revenue_monthly` AS

WITH monthly_rollup AS (
    SELECT
        DATE_TRUNC(order_date, MONTH) AS order_month,

        SUM(submitted_orders) AS submitted_orders,
        SUM(completed_orders) AS completed_orders,
        SUM(cancelled_orders) AS cancelled_orders,
        SUM(shopify_completed_orders) AS shopify_completed_orders,
        SUM(etsy_completed_orders) AS etsy_completed_orders,
        SUM(channel_scoped_customers) AS channel_scoped_customers,
        SUM(refunded_orders) AS refunded_orders,
        SUM(edge_case_orders) AS edge_case_orders,
        SUM(etsy_orders_missing_payment) AS etsy_orders_missing_payment,
        SUM(total_units_sold) AS total_units_sold,

        ROUND(SUM(total_gross_revenue), 2) AS total_gross_revenue,
        ROUND(SUM(total_refunded_amount), 2) AS total_refunded_amount,
        ROUND(SUM(total_fee_amount), 2) AS total_fee_amount,
        ROUND(SUM(total_net_revenue_after_refunds), 2) AS total_net_revenue_after_refunds,
        ROUND(SUM(total_channel_reported_net_amount), 2) AS total_channel_reported_net_amount,

        ROUND(SUM(shopify_gross_revenue), 2) AS shopify_gross_revenue,
        ROUND(SUM(etsy_gross_revenue), 2) AS etsy_gross_revenue,
        ROUND(SUM(shopify_net_revenue_after_refunds), 2) AS shopify_net_revenue_after_refunds,
        ROUND(SUM(etsy_net_revenue_after_refunds), 2) AS etsy_net_revenue_after_refunds

    FROM `mischief-made-analytics.marts.anl_dashboard_revenue_daily`
    GROUP BY DATE_TRUNC(order_date, MONTH)
),

final AS (
    SELECT
        order_month,
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
        ROUND(SAFE_DIVIDE(etsy_net_revenue_after_refunds, total_net_revenue_after_refunds), 4) AS etsy_net_revenue_share,

        LAG(total_net_revenue_after_refunds) OVER (ORDER BY order_month) AS prior_month_net_revenue,

        total_net_revenue_after_refunds
            - LAG(total_net_revenue_after_refunds) OVER (ORDER BY order_month)
            AS net_revenue_mom_change,

        ROUND(
            SAFE_DIVIDE(
                total_net_revenue_after_refunds
                    - LAG(total_net_revenue_after_refunds) OVER (ORDER BY order_month),
                LAG(total_net_revenue_after_refunds) OVER (ORDER BY order_month)
            ),
            4
        ) AS net_revenue_mom_pct_change,

        LAG(completed_orders) OVER (ORDER BY order_month) AS prior_month_completed_orders,

        completed_orders
            - LAG(completed_orders) OVER (ORDER BY order_month)
            AS completed_orders_mom_change,

        ROUND(
            SAFE_DIVIDE(
                completed_orders
                    - LAG(completed_orders) OVER (ORDER BY order_month),
                LAG(completed_orders) OVER (ORDER BY order_month)
            ),
            4
        ) AS completed_orders_mom_pct_change

    FROM monthly_rollup
)

SELECT *
FROM final
ORDER BY order_month;