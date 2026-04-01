-- sql/analysis/customer_cohort_retention.sql
-- Purpose:
-- Customer cohort retention view for Analysis Pack v1.
--
-- Grain:
-- One row per cohort_month x months_since_first_order.
--
-- Notes:
-- - Built from marts.fct_orders as the source of truth for customer order activity
-- - Uses customer_email as the practical customer key
-- - Includes only non-cancelled orders
-- - Cohorts are based on first completed-order month

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_customer_cohort_retention` AS

WITH completed_orders AS (
    SELECT
        customer_email,
        order_number,
        DATE(created_at_ts) AS order_date,
        DATE_TRUNC(DATE(created_at_ts), MONTH) AS order_month,
        order_total
    FROM `mischief-made-analytics.marts.fct_orders`
WHERE customer_email IS NOT NULL
  AND TRIM(customer_email) <> ''
  AND cancelled_at_ts IS NULL
  AND LOWER(COALESCE(financial_status, '')) NOT IN ('voided', 'cancelled')
  AND is_suspect_historical_timing = FALSE
),

customer_first_order AS (
    SELECT
        customer_email,
        MIN(order_month) AS cohort_month
    FROM completed_orders
    GROUP BY customer_email
),

cohort_activity AS (
    SELECT
        cfo.cohort_month,
        co.order_month,
        DATE_DIFF(co.order_month, cfo.cohort_month, MONTH) AS months_since_first_order,
        co.customer_email,
        co.order_number,
        co.order_total
    FROM completed_orders co
    INNER JOIN customer_first_order cfo
        ON co.customer_email = cfo.customer_email
),

cohort_sizes AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT customer_email) AS customers_in_cohort
    FROM customer_first_order
    GROUP BY cohort_month
),

cohort_rollup AS (
    SELECT
        cohort_month,
        months_since_first_order,
        COUNT(DISTINCT customer_email) AS customers_ordering_in_period,
        COUNT(DISTINCT order_number) AS period_orders,
        ROUND(SUM(COALESCE(order_total, 0)), 2) AS period_revenue
    FROM cohort_activity
    GROUP BY cohort_month, months_since_first_order
)

SELECT
    cr.cohort_month,
    cr.months_since_first_order,
    cs.customers_in_cohort,
    cr.customers_ordering_in_period,
    ROUND(SAFE_DIVIDE(cr.customers_ordering_in_period, cs.customers_in_cohort), 4) AS retention_rate,
    cr.period_orders,
    cr.period_revenue
FROM cohort_rollup cr
INNER JOIN cohort_sizes cs
    ON cr.cohort_month = cs.cohort_month
ORDER BY cr.cohort_month, cr.months_since_first_order;
