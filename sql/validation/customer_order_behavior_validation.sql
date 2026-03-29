-- sql/validation/customer_order_behavior_validation.sql
-- Purpose:
-- Validation checks for marts.anl_customer_order_behavior

-- 1) Grain check: one row per customer_key
SELECT
    customer_key,
    COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.anl_customer_order_behavior`
GROUP BY customer_key
HAVING COUNT(*) > 1;


-- 2) Non-cancelled order count tieout to fct_orders
WITH behavior AS (
    SELECT
        SUM(lifetime_orders) AS behavior_lifetime_orders
    FROM `mischief-made-analytics.marts.anl_customer_order_behavior`
),
orders AS (
    SELECT
        COUNT(DISTINCT order_number) AS fact_lifetime_orders
    FROM `mischief-made-analytics.marts.fct_orders`
    WHERE customer_email IS NOT NULL
      AND TRIM(customer_email) <> ''
      AND cancelled_at_ts IS NULL
      AND LOWER(COALESCE(financial_status, '')) NOT IN ('voided', 'cancelled')
)
SELECT
    b.behavior_lifetime_orders,
    o.fact_lifetime_orders,
    b.behavior_lifetime_orders - o.fact_lifetime_orders AS diff
FROM behavior b
CROSS JOIN orders o;


-- 3) Revenue tieout to fct_orders for non-cancelled customer orders
WITH behavior AS (
    SELECT
        ROUND(SUM(lifetime_revenue), 2) AS behavior_lifetime_revenue
    FROM `mischief-made-analytics.marts.anl_customer_order_behavior`
),
orders AS (
    SELECT
        ROUND(SUM(COALESCE(order_total, 0)), 2) AS fact_lifetime_revenue
    FROM `mischief-made-analytics.marts.fct_orders`
    WHERE customer_email IS NOT NULL
      AND TRIM(customer_email) <> ''
      AND cancelled_at_ts IS NULL
      AND LOWER(COALESCE(financial_status, '')) NOT IN ('voided', 'cancelled')
)
SELECT
    b.behavior_lifetime_revenue,
    o.fact_lifetime_revenue,
    ROUND(b.behavior_lifetime_revenue - o.fact_lifetime_revenue, 2) AS diff
FROM behavior b
CROSS JOIN orders o;


-- 4) Submitted order count tieout
WITH behavior AS (
    SELECT
        SUM(submitted_orders) AS behavior_submitted_orders
    FROM `mischief-made-analytics.marts.anl_customer_order_behavior`
),
orders AS (
    SELECT
        COUNT(DISTINCT order_number) AS fact_submitted_orders
    FROM `mischief-made-analytics.marts.fct_orders`
    WHERE customer_email IS NOT NULL
      AND TRIM(customer_email) <> ''
)
SELECT
    b.behavior_submitted_orders,
    o.fact_submitted_orders,
    b.behavior_submitted_orders - o.fact_submitted_orders AS diff
FROM behavior b
CROSS JOIN orders o;


-- 5) Customer type distribution sanity check
SELECT
    customer_type,
    COUNT(*) AS customers,
    ROUND(SUM(lifetime_revenue), 2) AS total_revenue,
    ROUND(AVG(avg_order_value), 2) AS avg_aov
FROM `mischief-made-analytics.marts.anl_customer_order_behavior`
GROUP BY customer_type
ORDER BY customers DESC;
