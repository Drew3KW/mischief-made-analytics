-- sql/analysis/customer_rfm_segments_review.sql
-- Purpose:
-- Business-facing review queries for customer RFM segmentation.

-- 1) Customer counts and revenue by RFM segment
SELECT
    rfm_segment,
    COUNT(*) AS customers,
    ROUND(SUM(lifetime_revenue), 2) AS total_lifetime_revenue,
    ROUND(AVG(lifetime_revenue), 2) AS avg_lifetime_revenue,
    ROUND(AVG(avg_order_value), 2) AS avg_aov
FROM `mischief-made-analytics.marts.anl_customer_rfm_segments`
GROUP BY rfm_segment
ORDER BY total_lifetime_revenue DESC;

-- 2) Segment mix by recency, frequency, and monetary dimensions
SELECT
    recency_segment,
    frequency_segment,
    monetary_segment,
    COUNT(*) AS customers,
    ROUND(SUM(lifetime_revenue), 2) AS total_lifetime_revenue
FROM `mischief-made-analytics.marts.anl_customer_rfm_segments`
GROUP BY recency_segment, frequency_segment, monetary_segment
ORDER BY
    recency_segment,
    frequency_segment,
    monetary_segment;

-- 3) Top loyal / high-value customers
SELECT
    customer_email,
    first_name,
    last_name,
    most_recent_order_date,
    days_since_last_order,
    lifetime_orders,
    lifetime_revenue,
    avg_order_value,
    rfm_segment
FROM `mischief-made-analytics.marts.anl_customer_rfm_segments`
WHERE rfm_segment = 'loyal_high_value'
ORDER BY lifetime_revenue DESC
LIMIT 50;

-- 4) High-value lapsed customers for win-back
SELECT
    customer_email,
    first_name,
    last_name,
    most_recent_order_date,
    days_since_last_order,
    lifetime_orders,
    lifetime_revenue,
    avg_order_value,
    rfm_segment
FROM `mischief-made-analytics.marts.anl_customer_rfm_segments`
WHERE rfm_segment = 'lapsed_high_value'
ORDER BY lifetime_revenue DESC, days_since_last_order DESC
LIMIT 50;

-- 5) Recent one-time customers for second-purchase targeting
SELECT
    customer_email,
    first_name,
    last_name,
    first_order_date,
    most_recent_order_date,
    days_since_last_order,
    lifetime_orders,
    lifetime_revenue,
    avg_order_value,
    rfm_segment
FROM `mischief-made-analytics.marts.anl_customer_rfm_segments`
WHERE rfm_segment = 'recent_one_time'
ORDER BY most_recent_order_date DESC
LIMIT 50;
