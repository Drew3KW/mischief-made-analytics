-- sql/analysis/customer_order_behavior_review.sql
-- Purpose:
-- Business-facing review queries for customer order behavior.

-- 1) Repeat vs one-time customer mix
SELECT
    customer_type,
    COUNT(*) AS customers,
    ROUND(SUM(lifetime_revenue), 2) AS total_revenue,
    ROUND(AVG(lifetime_revenue), 2) AS avg_revenue_per_customer,
    ROUND(AVG(avg_order_value), 2) AS avg_aov
FROM `mischief-made-analytics.marts.anl_customer_order_behavior`
GROUP BY customer_type
ORDER BY customers DESC;


-- 2) Top customers by lifetime revenue
SELECT
    customer_email,
    first_name,
    last_name,
    lifetime_orders,
    lifetime_revenue,
    lifetime_net_revenue_after_refunds,
    avg_order_value,
    customer_type,
    most_recent_order_date
FROM `mischief-made-analytics.marts.anl_customer_order_behavior`
ORDER BY lifetime_revenue DESC
LIMIT 50;


-- 3) AOV distribution
SELECT
    CASE
        WHEN avg_order_value < 40 THEN 'under_40'
        WHEN avg_order_value < 60 THEN '40_to_59_99'
        WHEN avg_order_value < 80 THEN '60_to_79_99'
        WHEN avg_order_value < 100 THEN '80_to_99_99'
        ELSE '100_plus'
    END AS aov_band,
    COUNT(*) AS customers,
    ROUND(SUM(lifetime_revenue), 2) AS total_revenue
FROM `mischief-made-analytics.marts.anl_customer_order_behavior`
GROUP BY aov_band
ORDER BY aov_band;


-- 4) Customers with notable cancellation behavior
SELECT
    customer_email,
    submitted_orders,
    lifetime_orders,
    cancelled_orders,
    cancellation_rate,
    lifetime_revenue,
    most_recent_submitted_order_date
FROM `mischief-made-analytics.marts.anl_customer_order_behavior`
WHERE cancelled_orders > 0
ORDER BY cancellation_rate DESC, cancelled_orders DESC, submitted_orders DESC
LIMIT 50;


-- 5) Customers with refund activity
SELECT
    customer_email,
    lifetime_orders,
    refunded_orders,
    refund_rate,
    lifetime_revenue,
    lifetime_refunded_amount,
    lifetime_net_revenue_after_refunds,
    most_recent_refund_date
FROM `mischief-made-analytics.marts.anl_customer_order_behavior`
WHERE refunded_orders > 0
ORDER BY lifetime_refunded_amount DESC, refunded_orders DESC
LIMIT 50;
