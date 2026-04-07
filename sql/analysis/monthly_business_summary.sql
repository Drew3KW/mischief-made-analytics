-- sql/analysis/monthly_business_summary.sql
-- Purpose:
-- Dashboard-ready monthly business summary view for Analysis Pack v1.
--
-- Grain:
-- One row per order_month.
--
-- Notes:
-- - Built on top of marts.anl_daily_kpi_summary
-- - Recomputes blended monthly KPI ratios from additive monthly totals
-- - Adds month-over-month comparison fields

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_monthly_business_summary` AS

WITH monthly_rollup AS (
    SELECT
        DATE_TRUNC(order_date, MONTH) AS order_month,

        SUM(submitted_orders) AS submitted_orders,
        SUM(completed_orders) AS completed_orders,
        SUM(cancelled_orders) AS cancelled_orders,
        SUM(units_sold) AS units_sold,

        SUM(customers_submitting_orders) AS customers_submitting_orders,
        SUM(customers_with_completed_orders) AS customers_with_completed_orders,
        SUM(new_customers) AS new_customers,
        SUM(returning_customers) AS returning_customers,

        ROUND(SUM(gross_revenue), 2) AS gross_revenue,
        ROUND(SUM(refunded_amount), 2) AS refunded_amount,
        ROUND(SUM(net_revenue_after_refunds), 2) AS net_revenue_after_refunds,
        ROUND(SUM(gross_item_revenue), 2) AS gross_item_revenue,
        ROUND(SUM(net_item_revenue_before_refunds), 2) AS net_item_revenue_before_refunds,
        ROUND(
            SAFE_DIVIDE(
                SUM(refund_rate * completed_orders),
                SUM(completed_orders)
            ),
            4
        ) AS refund_rate
    FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
    GROUP BY DATE_TRUNC(order_date, MONTH)
),

final AS (
    SELECT
        order_month,
        submitted_orders,
        completed_orders,
        cancelled_orders,
        units_sold,
        customers_submitting_orders,
        customers_with_completed_orders,
        new_customers,
        returning_customers,
        gross_revenue,
        refunded_amount,
        net_revenue_after_refunds,
        gross_item_revenue,
        net_item_revenue_before_refunds,

        ROUND(SAFE_DIVIDE(gross_revenue, completed_orders), 2) AS avg_order_value,
        ROUND(SAFE_DIVIDE(units_sold, completed_orders), 2) AS avg_units_per_order,
        ROUND(SAFE_DIVIDE(gross_revenue, customers_with_completed_orders), 2) AS revenue_per_completed_customer,
        ROUND(SAFE_DIVIDE(cancelled_orders, submitted_orders), 4) AS cancellation_rate,
        refund_rate,

        LAG(net_revenue_after_refunds) OVER (ORDER BY order_month) AS prior_month_net_revenue,
        net_revenue_after_refunds
            - LAG(net_revenue_after_refunds) OVER (ORDER BY order_month) AS net_revenue_mom_change,
        ROUND(
            SAFE_DIVIDE(
                net_revenue_after_refunds
                    - LAG(net_revenue_after_refunds) OVER (ORDER BY order_month),
                LAG(net_revenue_after_refunds) OVER (ORDER BY order_month)
            ),
            4
        ) AS net_revenue_mom_pct_change,

        LAG(completed_orders) OVER (ORDER BY order_month) AS prior_month_completed_orders,
        completed_orders
            - LAG(completed_orders) OVER (ORDER BY order_month) AS completed_orders_mom_change,
        ROUND(
            SAFE_DIVIDE(
                completed_orders
                    - LAG(completed_orders) OVER (ORDER BY order_month),
                LAG(completed_orders) OVER (ORDER BY order_month)
            ),
            4
        ) AS completed_orders_mom_pct_change,

        LAG(customers_with_completed_orders) OVER (ORDER BY order_month) AS prior_month_customers_with_completed_orders,
        customers_with_completed_orders
            - LAG(customers_with_completed_orders) OVER (ORDER BY order_month) AS customers_mom_change,
        ROUND(
            SAFE_DIVIDE(
                customers_with_completed_orders
                    - LAG(customers_with_completed_orders) OVER (ORDER BY order_month),
                LAG(customers_with_completed_orders) OVER (ORDER BY order_month)
            ),
            4
        ) AS customers_mom_pct_change
    FROM monthly_rollup
)

SELECT
    order_month,
    submitted_orders,
    completed_orders,
    cancelled_orders,
    units_sold,
    customers_submitting_orders,
    customers_with_completed_orders,
    new_customers,
    returning_customers,
    gross_revenue,
    refunded_amount,
    net_revenue_after_refunds,
    gross_item_revenue,
    net_item_revenue_before_refunds,
    avg_order_value,
    avg_units_per_order,
    revenue_per_completed_customer,
    cancellation_rate,
    refund_rate,
    prior_month_net_revenue,
    net_revenue_mom_change,
    net_revenue_mom_pct_change,
    prior_month_completed_orders,
    completed_orders_mom_change,
    completed_orders_mom_pct_change,
    prior_month_customers_with_completed_orders,
    customers_mom_change,
    customers_mom_pct_change
FROM final
ORDER BY order_month;
