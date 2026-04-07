-- sql/analysis/monthly_business_summary_review.sql
-- Purpose:
-- Business-facing review queries for marts.anl_monthly_business_summary.

-- 1) Full monthly trend
SELECT
    order_month,
    submitted_orders,
    completed_orders,
    cancelled_orders,
    units_sold,
    customers_with_completed_orders,
    new_customers,
    returning_customers,
    gross_revenue,
    refunded_amount,
    net_revenue_after_refunds,
    avg_order_value,
    avg_units_per_order,
    revenue_per_completed_customer,
    cancellation_rate,
    refund_rate,
    net_revenue_mom_change,
    net_revenue_mom_pct_change
FROM `mischief-made-analytics.marts.anl_monthly_business_summary`
ORDER BY order_month DESC;

-- 2) Best revenue months
SELECT
    order_month,
    completed_orders,
    customers_with_completed_orders,
    gross_revenue,
    refunded_amount,
    net_revenue_after_refunds,
    avg_order_value
FROM `mischief-made-analytics.marts.anl_monthly_business_summary`
ORDER BY net_revenue_after_refunds DESC
LIMIT 24;

-- 3) Highest order-volume months
SELECT
    order_month,
    submitted_orders,
    completed_orders,
    cancelled_orders,
    units_sold,
    customers_with_completed_orders,
    gross_revenue,
    net_revenue_after_refunds
FROM `mischief-made-analytics.marts.anl_monthly_business_summary`
ORDER BY completed_orders DESC, submitted_orders DESC
LIMIT 24;

-- 4) New vs returning customer mix by month
SELECT
    order_month,
    customers_with_completed_orders,
    new_customers,
    returning_customers,
    ROUND(SAFE_DIVIDE(new_customers, customers_with_completed_orders), 4) AS pct_new_customers,
    ROUND(SAFE_DIVIDE(returning_customers, customers_with_completed_orders), 4) AS pct_returning_customers,
    net_revenue_after_refunds
FROM `mischief-made-analytics.marts.anl_monthly_business_summary`
ORDER BY order_month DESC;

-- 5) MoM revenue and order trend
SELECT
    order_month,
    net_revenue_after_refunds,
    prior_month_net_revenue,
    net_revenue_mom_change,
    net_revenue_mom_pct_change,
    completed_orders,
    prior_month_completed_orders,
    completed_orders_mom_change,
    completed_orders_mom_pct_change
FROM `mischief-made-analytics.marts.anl_monthly_business_summary`
ORDER BY order_month DESC;

-- 6) Months with highest cancellation rate
SELECT
    order_month,
    submitted_orders,
    cancelled_orders,
    cancellation_rate,
    gross_revenue,
    net_revenue_after_refunds
FROM `mischief-made-analytics.marts.anl_monthly_business_summary`
WHERE submitted_orders > 0
ORDER BY cancellation_rate DESC, submitted_orders DESC
LIMIT 24;

-- 7) Months with highest refund rate
SELECT
    order_month,
    completed_orders,
    refunded_amount,
    refund_rate,
    gross_revenue,
    net_revenue_after_refunds
FROM `mischief-made-analytics.marts.anl_monthly_business_summary`
WHERE completed_orders > 0
ORDER BY refund_rate DESC, completed_orders DESC
LIMIT 24;

-- 8) Year-over-year month-of-year pattern
SELECT
    EXTRACT(MONTH FROM order_month) AS month_of_year,
    COUNT(*) AS months_present,
    ROUND(AVG(net_revenue_after_refunds), 2) AS avg_monthly_net_revenue,
    ROUND(AVG(completed_orders), 2) AS avg_monthly_completed_orders,
    ROUND(AVG(customers_with_completed_orders), 2) AS avg_monthly_customers,
    ROUND(AVG(avg_order_value), 2) AS avg_monthly_aov
FROM `mischief-made-analytics.marts.anl_monthly_business_summary`
GROUP BY month_of_year
ORDER BY month_of_year;
