-- sql/analysis/family_summary_review.sql
-- Purpose:
-- Business-facing review queries for marts.anl_family_summary.

-- 1) Full monthly family summary trend
SELECT
    reporting_month,
    product_family_name,
    gross_family_revenue,
    orders_with_family,
    customers_with_family_orders,
    units_sold,
    revenue_share_of_month,
    family_trend_status
FROM `mischief-made-analytics.marts.anl_family_summary`
ORDER BY reporting_month DESC, gross_family_revenue DESC;

-- 2) Top families by monthly revenue
SELECT
    reporting_month,
    product_family_name,
    gross_family_revenue,
    revenue_share_of_month,
    prior_month_gross_family_revenue,
    gross_family_revenue_mom_pct_change,
    family_revenue_tier,
    family_trend_status
FROM `mischief-made-analytics.marts.anl_family_summary`
ORDER BY gross_family_revenue DESC, reporting_month DESC
LIMIT 50;

-- 3) Highest customer-reach families by month
SELECT
    reporting_month,
    product_family_name,
    customers_with_family_orders,
    customers_share_of_month,
    new_customers,
    returning_customers,
    new_customer_rate,
    returning_customer_rate,
    family_customer_reach_tier
FROM `mischief-made-analytics.marts.anl_family_summary`
ORDER BY reporting_month DESC, customers_with_family_orders DESC;

-- 4) Families with strongest repeat-customer profile
SELECT
    reporting_month,
    product_family_name,
    customers_with_family_orders,
    pct_repeat_customers,
    avg_customer_lifetime_revenue,
    avg_customer_lifetime_orders,
    gross_family_revenue
FROM `mischief-made-analytics.marts.anl_family_summary`
ORDER BY pct_repeat_customers DESC, gross_family_revenue DESC;

-- 5) Families with strongest MoM revenue growth
SELECT
    reporting_month,
    product_family_name,
    gross_family_revenue,
    prior_month_gross_family_revenue,
    gross_family_revenue_mom_change,
    gross_family_revenue_mom_pct_change,
    family_trend_status
FROM `mischief-made-analytics.marts.anl_family_summary`
WHERE prior_month_gross_family_revenue IS NOT NULL
ORDER BY gross_family_revenue_mom_pct_change DESC, gross_family_revenue DESC
LIMIT 50;

-- 6) Families contributing the most share of month
SELECT
    reporting_month,
    product_family_name,
    gross_family_revenue,
    revenue_share_of_month,
    orders_share_of_month,
    customers_share_of_month,
    units_share_of_month
FROM `mischief-made-analytics.marts.anl_family_summary`
ORDER BY reporting_month DESC, revenue_share_of_month DESC;

-- 7) New-customer-heavy families
SELECT
    reporting_month,
    product_family_name,
    new_customers,
    customers_with_family_orders,
    new_customer_rate,
    gross_family_revenue,
    revenue_share_of_month
FROM `mischief-made-analytics.marts.anl_family_summary`
ORDER BY new_customer_rate DESC, gross_family_revenue DESC;

-- 8) Families that are often a customer's first family purchase
SELECT
    reporting_month,
    product_family_name,
    customers_first_buying_this_family,
    pct_of_family_customers_first_buying_this_family,
    customers_who_bought_family,
    pct_repeat_customers
FROM `mischief-made-analytics.marts.anl_family_summary`
ORDER BY pct_of_family_customers_first_buying_this_family DESC, customers_who_bought_family DESC;
