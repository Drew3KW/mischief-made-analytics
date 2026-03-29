-- sql/validation/customer_recency_segments_validation.sql
-- Purpose:
-- Validation checks for marts.anl_customer_recency_segments

-- 1) Grain check
SELECT
    customer_key,
    COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.anl_customer_recency_segments`
GROUP BY customer_key
HAVING COUNT(*) > 1;


-- 2) Row-count tieout to customer behavior model
WITH recency AS (
    SELECT COUNT(*) AS recency_rows
    FROM `mischief-made-analytics.marts.anl_customer_recency_segments`
),
behavior AS (
    SELECT COUNT(*) AS behavior_rows
    FROM `mischief-made-analytics.marts.anl_customer_order_behavior`
)
SELECT
    r.recency_rows,
    b.behavior_rows,
    r.recency_rows - b.behavior_rows AS diff
FROM recency r
CROSS JOIN behavior b;


-- 3) Revenue tieout to customer behavior model
WITH recency AS (
    SELECT ROUND(SUM(lifetime_revenue), 2) AS recency_revenue
    FROM `mischief-made-analytics.marts.anl_customer_recency_segments`
),
behavior AS (
    SELECT ROUND(SUM(lifetime_revenue), 2) AS behavior_revenue
    FROM `mischief-made-analytics.marts.anl_customer_order_behavior`
)
SELECT
    r.recency_revenue,
    b.behavior_revenue,
    ROUND(r.recency_revenue - b.behavior_revenue, 2) AS diff
FROM recency r
CROSS JOIN behavior b;


-- 4) Segment coverage sanity check
SELECT
    recency_segment,
    COUNT(*) AS customers
FROM `mischief-made-analytics.marts.anl_customer_recency_segments`
GROUP BY recency_segment
ORDER BY customers DESC;
