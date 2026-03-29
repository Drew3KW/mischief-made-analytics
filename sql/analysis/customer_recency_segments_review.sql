-- sql/analysis/customer_recency_segments_review.sql
-- Purpose:
-- Business-facing review queries for customer recency and lifecycle segmentation.

-- 1) Customer counts and revenue by recency segment
SELECT
    recency_segment,
    COUNT(*) AS customers,
    ROUND(SUM(lifetime_revenue), 2) AS total_revenue,
    ROUND(AVG(lifetime_revenue), 2) AS avg_revenue_per_customer,
    ROUND(AVG(avg_order_value), 2) AS avg_aov
FROM `mischief-made-analytics.marts.anl_customer_recency_segments`
GROUP BY recency_segment
ORDER BY
    CASE recency_segment
        WHEN 'active_recent' THEN 1
        WHEN 'warm' THEN 2
        WHEN 'cooling_off' THEN 3
        WHEN 'lapsed' THEN 4
        ELSE 5
    END;


-- 2) Recency x customer type
SELECT
    recency_segment,
    customer_type,
    COUNT(*) AS customers,
    ROUND(SUM(lifetime_revenue), 2) AS total_revenue
FROM `mischief-made-analytics.marts.anl_customer_recency_segments`
GROUP BY recency_segment, customer_type
ORDER BY
    CASE recency_segment
        WHEN 'active_recent' THEN 1
        WHEN 'warm' THEN 2
        WHEN 'cooling_off' THEN 3
        WHEN 'lapsed' THEN 4
        ELSE 5
    END,
    customer_type;


-- 3) Top lapsed customers by lifetime revenue
SELECT
    customer_email,
    first_name,
    last_name,
    most_recent_order_date,
    days_since_last_order,
    lifetime_orders,
    lifetime_revenue,
    avg_order_value,
    customer_type
FROM `mischief-made-analytics.marts.anl_customer_recency_segments`
WHERE recency_segment = 'lapsed'
ORDER BY lifetime_revenue DESC
LIMIT 50;


-- 4) High-value active customers
SELECT
    customer_email,
    first_name,
    last_name,
    most_recent_order_date,
    days_since_last_order,
    lifetime_orders,
    lifetime_revenue,
    avg_order_value
FROM `mischief-made-analytics.marts.anl_customer_recency_segments`
WHERE recency_segment = 'active_recent'
  AND value_segment = 'high_value'
ORDER BY lifetime_revenue DESC
LIMIT 50;
