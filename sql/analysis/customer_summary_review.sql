-- sql/analysis/customer_summary_review.sql
-- Purpose:
-- Business-facing review queries for marts.anl_customer_summary.

-- 1) Full monthly customer summary trend
SELECT
    reporting_month,
    total_customers,
    customers_with_completed_orders,
    new_customers,
    returning_customers,
    repeat_customers,
    loyal_customers,
    net_revenue_in_month,
    avg_lifetime_value_customer_base,
    repeat_customer_rate,
    loyal_customer_rate,
    active_customer_rate
FROM `mischief-made-analytics.marts.anl_customer_summary`
ORDER BY reporting_month DESC;

-- 2) Customer acquisition mix by month
SELECT
    reporting_month,
    customers_with_completed_orders,
    new_customers,
    returning_customers,
    pct_new_customers,
    pct_returning_customers,
    new_customer_net_revenue_in_month,
    returning_customer_net_revenue_in_month
FROM `mischief-made-analytics.marts.anl_customer_summary`
ORDER BY reporting_month DESC;

-- 3) Customer-base composition over time
SELECT
    reporting_month,
    total_customers,
    one_time_customers,
    repeat_customers,
    loyal_customers,
    repeat_customer_rate,
    loyal_customer_rate
FROM `mischief-made-analytics.marts.anl_customer_summary`
ORDER BY reporting_month DESC;

-- 4) Recency mix over time
SELECT
    reporting_month,
    total_customers,
    active_recent_customers,
    warm_customers,
    cooling_off_customers,
    lapsed_customers,
    ROUND(SAFE_DIVIDE(active_recent_customers, total_customers), 4) AS pct_active_recent,
    ROUND(SAFE_DIVIDE(lapsed_customers, total_customers), 4) AS pct_lapsed
FROM `mischief-made-analytics.marts.anl_customer_summary`
ORDER BY reporting_month DESC;

-- 5) Value mix over time
SELECT
    reporting_month,
    total_customers,
    high_value_customers,
    mid_value_customers,
    low_value_customers,
    ROUND(SAFE_DIVIDE(high_value_customers, total_customers), 4) AS pct_high_value,
    avg_lifetime_value_customer_base
FROM `mischief-made-analytics.marts.anl_customer_summary`
ORDER BY reporting_month DESC;

-- 6) Flagship RFM-style segment counts
SELECT
    reporting_month,
    loyal_high_value_customers,
    recent_one_time_customers,
    lapsed_high_value_customers
FROM `mischief-made-analytics.marts.anl_customer_summary`
ORDER BY reporting_month DESC;

-- 7) Strongest active-customer months
SELECT
    reporting_month,
    customers_with_completed_orders,
    new_customers,
    returning_customers,
    net_revenue_in_month,
    revenue_per_active_customer,
    active_customer_rate
FROM `mischief-made-analytics.marts.anl_customer_summary`
ORDER BY customers_with_completed_orders DESC, net_revenue_in_month DESC
LIMIT 24;

-- 8) MoM customer-base growth
SELECT
    reporting_month,
    total_customers,
    prior_month_total_customers,
    total_customers_mom_change,
    total_customers_mom_pct_change,
    customers_with_completed_orders,
    prior_month_active_customers,
    active_customers_mom_change,
    active_customers_mom_pct_change,
    net_revenue_in_month,
    prior_month_net_revenue_in_month,
    net_revenue_mom_change,
    net_revenue_mom_pct_change
FROM `mischief-made-analytics.marts.anl_customer_summary`
ORDER BY reporting_month DESC;
