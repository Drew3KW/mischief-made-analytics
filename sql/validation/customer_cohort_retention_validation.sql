-- sql/validation/customer_cohort_retention_validation.sql
-- Purpose:
-- Validation checks for marts.anl_customer_cohort_retention

-- 1) Ensure there is only one row per cohort_month x months_since_first_order
SELECT
    cohort_month,
    months_since_first_order,
    COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.anl_customer_cohort_retention_trusted_dates`
GROUP BY cohort_month, months_since_first_order
HAVING COUNT(*) > 1;


-- 2) Month 0 customers should equal cohort size
SELECT
    cohort_month,
    customers_in_cohort,
    customers_ordering_in_period,
    customers_in_cohort - customers_ordering_in_period AS diff
FROM `mischief-made-analytics.marts.anl_customer_cohort_retention_trusted_dates`
WHERE months_since_first_order = 0
  AND customers_in_cohort != customers_ordering_in_period;


-- 3) Month 0 retention should be 1.0000
SELECT
    cohort_month,
    retention_rate
FROM `mischief-made-analytics.marts.anl_customer_cohort_retention_trusted_dates`
WHERE months_since_first_order = 0
  AND retention_rate != 1.0000;


-- 4) Retention rate should never exceed 1
SELECT
    cohort_month,
    months_since_first_order,
    retention_rate
FROM `mischief-made-analytics.marts.anl_customer_cohort_retention_trusted_dates`
WHERE retention_rate > 1.0000;


-- 5) Cohort sizes tie out to distinct trusted completed-order customers
WITH cohorts AS (
    SELECT
        SUM(
            CASE
                WHEN months_since_first_order = 0 THEN customers_in_cohort
                ELSE 0
            END
        ) AS total_cohort_customers
    FROM `mischief-made-analytics.marts.anl_customer_cohort_retention_trusted_dates`
),
orders AS (
    SELECT
        COUNT(DISTINCT customer_email) AS distinct_completed_order_customers
    FROM `mischief-made-analytics.marts.fct_orders`
    WHERE customer_email IS NOT NULL
      AND TRIM(customer_email) <> ''
      AND cancelled_at_ts IS NULL
      AND LOWER(COALESCE(financial_status, '')) NOT IN ('voided', 'cancelled')
      AND is_suspect_historical_timing = FALSE
)
SELECT
    c.total_cohort_customers,
    o.distinct_completed_order_customers,
    c.total_cohort_customers - o.distinct_completed_order_customers AS diff
FROM cohorts c
CROSS JOIN orders o;
