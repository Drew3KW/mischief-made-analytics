-- sql/validation/customer_rfm_segments_validation.sql
-- Purpose:
-- Validation checks for marts.anl_customer_rfm_segments

-- 1) Grain check
SELECT
    customer_key,
    COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.anl_customer_rfm_segments`
GROUP BY customer_key
HAVING COUNT(*) > 1;

-- 2) Row-count tieout to customer behavior model
WITH rfm AS (
    SELECT COUNT(*) AS rfm_rows
    FROM `mischief-made-analytics.marts.anl_customer_rfm_segments`
),
behavior AS (
    SELECT COUNT(*) AS behavior_rows
    FROM `mischief-made-analytics.marts.anl_customer_order_behavior`
)
SELECT
    rfm.rfm_rows,
    behavior.behavior_rows,
    rfm.rfm_rows - behavior.behavior_rows AS diff
FROM rfm
CROSS JOIN behavior;

-- 3) Revenue tieout to customer behavior model
WITH rfm AS (
    SELECT ROUND(SUM(lifetime_revenue), 2) AS rfm_revenue
    FROM `mischief-made-analytics.marts.anl_customer_rfm_segments`
),
behavior AS (
    SELECT ROUND(SUM(lifetime_revenue), 2) AS behavior_revenue
    FROM `mischief-made-analytics.marts.anl_customer_order_behavior`
)
SELECT
    rfm.rfm_revenue,
    behavior.behavior_revenue,
    ROUND(rfm.rfm_revenue - behavior.behavior_revenue, 2) AS diff
FROM rfm
CROSS JOIN behavior;

-- 4) Recency tieout to recency model
WITH rfm AS (
    SELECT
        customer_key,
        recency_segment,
        days_since_last_order
    FROM `mischief-made-analytics.marts.anl_customer_rfm_segments`
),
recency AS (
    SELECT
        customer_key,
        recency_segment,
        days_since_last_order
    FROM `mischief-made-analytics.marts.anl_customer_recency_segments`
)
SELECT
    COUNT(*) AS mismatched_rows
FROM rfm
INNER JOIN recency
    ON rfm.customer_key = recency.customer_key
WHERE rfm.recency_segment != recency.recency_segment
   OR rfm.days_since_last_order != recency.days_since_last_order;

-- 5) Null / coverage sanity checks
SELECT
    COUNTIF(recency_segment IS NULL) AS null_recency_segment_rows,
    COUNTIF(frequency_segment IS NULL) AS null_frequency_segment_rows,
    COUNTIF(monetary_segment IS NULL) AS null_monetary_segment_rows,
    COUNTIF(rfm_segment IS NULL) AS null_rfm_segment_rows
FROM `mischief-made-analytics.marts.anl_customer_rfm_segments`;

-- 6) Segment distribution sanity check
SELECT
    rfm_segment,
    COUNT(*) AS customers,
    ROUND(SUM(lifetime_revenue), 2) AS total_lifetime_revenue
FROM `mischief-made-analytics.marts.anl_customer_rfm_segments`
GROUP BY rfm_segment
ORDER BY customers DESC;
