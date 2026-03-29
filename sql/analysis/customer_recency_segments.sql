-- sql/analysis/customer_recency_segments.sql
-- Purpose:
-- Customer-level recency and lifecycle segmentation view for Analysis Pack v1.
--
-- Grain:
-- One row per customer.
--
-- Notes:
-- - Built on top of marts.anl_customer_order_behavior
-- - Recency is measured from most_recent_order_date
-- - Segment thresholds are intentionally simple and business-readable

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_customer_recency_segments` AS

SELECT
    customer_key,
    customer_email,
    shopify_customer_id,
    first_name,
    last_name,
    accepts_email_marketing,
    accepts_sms_marketing,
    default_address_city,
    default_address_province_code,
    default_address_country_code,

    first_order_date,
    most_recent_order_date,
    lifetime_orders,
    lifetime_revenue,
    lifetime_net_revenue_after_refunds,
    avg_order_value,
    customer_type,

    DATE_DIFF(CURRENT_DATE(), most_recent_order_date, DAY) AS days_since_last_order,

    CASE
        WHEN most_recent_order_date IS NULL THEN 'no_completed_orders'
        WHEN DATE_DIFF(CURRENT_DATE(), most_recent_order_date, DAY) <= 90 THEN 'active_recent'
        WHEN DATE_DIFF(CURRENT_DATE(), most_recent_order_date, DAY) <= 180 THEN 'warm'
        WHEN DATE_DIFF(CURRENT_DATE(), most_recent_order_date, DAY) <= 365 THEN 'cooling_off'
        ELSE 'lapsed'
    END AS recency_segment,

    CASE
        WHEN lifetime_revenue >= 500 THEN 'high_value'
        WHEN lifetime_revenue >= 150 THEN 'mid_value'
        ELSE 'lower_value'
    END AS value_segment

FROM `mischief-made-analytics.marts.anl_customer_order_behavior`;
