-- sql/analysis/daily_kpi_summary_review.sql
-- Purpose:
-- Business-facing review queries for marts.anl_daily_kpi_summary.

-- 1) Most recent 60 days of daily KPI trend
SELECT
    order_date,
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
    cancellation_rate,
    refund_rate,
    avg_units_per_order,
    revenue_per_completed_customer
FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
ORDER BY order_date DESC
LIMIT 60;

-- 2) Highest revenue days
SELECT
    order_date,
    completed_orders,
    units_sold,
    customers_with_completed_orders,
    gross_revenue,
    refunded_amount,
    net_revenue_after_refunds,
    avg_order_value
FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
ORDER BY net_revenue_after_refunds DESC
LIMIT 30;

-- 3) Highest order-volume days
SELECT
    order_date,
    submitted_orders,
    completed_orders,
    cancelled_orders,
    units_sold,
    customers_with_completed_orders,
    gross_revenue,
    net_revenue_after_refunds
FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
ORDER BY completed_orders DESC, submitted_orders DESC
LIMIT 30;

-- 4) Days with highest cancellation rate
SELECT
    order_date,
    submitted_orders,
    completed_orders,
    cancelled_orders,
    cancellation_rate,
    gross_revenue,
    net_revenue_after_refunds
FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
WHERE submitted_orders > 0
ORDER BY cancellation_rate DESC, submitted_orders DESC
LIMIT 30;

-- 5) Days with highest refund rate
SELECT
    order_date,
    completed_orders,
    refunded_amount,
    refund_rate,
    gross_revenue,
    net_revenue_after_refunds
FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
WHERE completed_orders > 0
ORDER BY refund_rate DESC, completed_orders DESC
LIMIT 30;

-- 6) Daily new vs returning customer mix
SELECT
    order_date,
    customers_with_completed_orders,
    new_customers,
    returning_customers,
    ROUND(SAFE_DIVIDE(new_customers, customers_with_completed_orders), 4) AS pct_new_customers,
    ROUND(SAFE_DIVIDE(returning_customers, customers_with_completed_orders), 4) AS pct_returning_customers,
    gross_revenue,
    net_revenue_after_refunds
FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
ORDER BY order_date DESC
LIMIT 90;

-- 7) Monthly rollup from daily KPI summary
SELECT
    DATE_TRUNC(order_date, MONTH) AS order_month,
    SUM(submitted_orders) AS submitted_orders,
    SUM(completed_orders) AS completed_orders,
    SUM(cancelled_orders) AS cancelled_orders,
    SUM(units_sold) AS units_sold,
    SUM(customers_with_completed_orders) AS customer_days_with_completed_orders,
    SUM(new_customers) AS new_customers,
    SUM(returning_customers) AS returning_customers,
    ROUND(SUM(gross_revenue), 2) AS gross_revenue,
    ROUND(SUM(refunded_amount), 2) AS refunded_amount,
    ROUND(SUM(net_revenue_after_refunds), 2) AS net_revenue_after_refunds,
    ROUND(SAFE_DIVIDE(SUM(gross_revenue), SUM(completed_orders)), 2) AS blended_aov,
    ROUND(SAFE_DIVIDE(SUM(units_sold), SUM(completed_orders)), 2) AS blended_avg_units_per_order
FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
GROUP BY order_month
ORDER BY order_month DESC;

-- 8) Monthly seasonality by month number across years
SELECT
    EXTRACT(MONTH FROM order_date) AS month_of_year,
    COUNT(*) AS days_present,
    ROUND(AVG(net_revenue_after_refunds), 2) AS avg_daily_net_revenue,
    ROUND(AVG(completed_orders), 2) AS avg_daily_completed_orders,
    ROUND(AVG(customers_with_completed_orders), 2) AS avg_daily_customers,
    ROUND(AVG(avg_order_value), 2) AS avg_daily_aov
FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
GROUP BY month_of_year
ORDER BY month_of_year;
