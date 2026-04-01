-- sql/analysis/customer_cohort_retention_review.sql
-- Purpose:
-- Business-facing review queries for customer cohort retention.

-- 1) Full cohort retention table
SELECT
    cohort_month,
    months_since_first_order,
    customers_in_cohort,
    customers_ordering_in_period,
    retention_rate,
    period_orders,
    period_revenue
FROM `mischief-made-analytics.marts.anl_customer_cohort_retention`
ORDER BY cohort_month, months_since_first_order;


-- 2) Cohort month 0 sanity check
SELECT
    cohort_month,
    customers_in_cohort,
    customers_ordering_in_period,
    retention_rate,
    period_orders,
    period_revenue
FROM `mischief-made-analytics.marts.anl_customer_cohort_retention`
WHERE months_since_first_order = 0
ORDER BY cohort_month;


-- 3) Month 1 retention by cohort
SELECT
    cohort_month,
    customers_in_cohort,
    customers_ordering_in_period,
    retention_rate,
    period_revenue
FROM `mischief-made-analytics.marts.anl_customer_cohort_retention`
WHERE months_since_first_order = 1
ORDER BY cohort_month;


-- 4) Average retention by lifecycle month
SELECT
    months_since_first_order,
    ROUND(AVG(retention_rate), 4) AS avg_retention_rate,
    SUM(customers_ordering_in_period) AS customers_ordering,
    ROUND(SUM(period_revenue), 2) AS total_revenue
FROM `mischief-made-analytics.marts.anl_customer_cohort_retention`
GROUP BY months_since_first_order
ORDER BY months_since_first_order;
