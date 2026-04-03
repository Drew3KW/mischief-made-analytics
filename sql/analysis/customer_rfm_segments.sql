-- sql/analysis/customer_rfm_segments.sql
-- Purpose:
-- Business-facing customer RFM-style segmentation view for Analysis Pack v1.
--
-- Grain:
-- One row per customer.
--
-- Notes:
-- - Built on top of marts.anl_customer_order_behavior
-- - Reuses recency logic from marts.anl_customer_recency_segments
-- - Uses simple fixed thresholds for business readability
-- - customer_key currently equals normalized customer_email

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_customer_rfm_segments` AS

WITH base AS (
    SELECT
        cob.customer_key,
        cob.customer_email,
        cob.shopify_customer_id,
        cob.first_name,
        cob.last_name,
        cob.accepts_email_marketing,
        cob.accepts_sms_marketing,
        cob.default_address_city,
        cob.default_address_province_code,
        cob.default_address_country_code,
        cob.first_order_date,
        cob.most_recent_order_date,
        cob.first_submitted_order_date,
        cob.most_recent_submitted_order_date,
        cob.submitted_orders,
        cob.lifetime_orders,
        cob.cancelled_orders,
        cob.refunded_orders,
        cob.lifetime_revenue,
        cob.lifetime_refunded_amount,
        cob.lifetime_net_revenue_after_refunds,
        cob.avg_order_value,
        cob.customer_type,
        crs.days_since_last_order,
        crs.recency_segment
    FROM `mischief-made-analytics.marts.anl_customer_order_behavior` AS cob
    LEFT JOIN `mischief-made-analytics.marts.anl_customer_recency_segments` AS crs
        ON cob.customer_key = crs.customer_key
),

segmented AS (
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
        first_submitted_order_date,
        most_recent_submitted_order_date,
        submitted_orders,
        lifetime_orders,
        cancelled_orders,
        refunded_orders,
        lifetime_revenue,
        lifetime_refunded_amount,
        lifetime_net_revenue_after_refunds,
        avg_order_value,
        customer_type,
        days_since_last_order,
        recency_segment,

        CASE
            WHEN lifetime_orders >= 5 THEN 'loyal'
            WHEN lifetime_orders >= 3 THEN 'repeat'
            WHEN lifetime_orders = 2 THEN 'occasional_repeat'
            WHEN lifetime_orders = 1 THEN 'one_time'
            ELSE 'no_completed_orders'
        END AS frequency_segment,

        CASE
            WHEN lifetime_orders = 0 OR lifetime_orders IS NULL THEN 'no_completed_orders'
            WHEN lifetime_revenue >= 500 THEN 'high_value'
            WHEN lifetime_revenue >= 150 THEN 'mid_value'
            ELSE 'low_value'
        END AS monetary_segment,

        CASE
            WHEN recency_segment = 'active_recent' THEN 4
            WHEN recency_segment = 'warm' THEN 3
            WHEN recency_segment = 'cooling_off' THEN 2
            WHEN recency_segment = 'lapsed' THEN 1
            ELSE NULL
        END AS recency_score,

        CASE
            WHEN lifetime_orders >= 5 THEN 4
            WHEN lifetime_orders >= 3 THEN 3
            WHEN lifetime_orders = 2 THEN 2
            WHEN lifetime_orders = 1 THEN 1
            ELSE NULL
        END AS frequency_score,

        CASE
            WHEN lifetime_orders = 0 OR lifetime_orders IS NULL THEN NULL
            WHEN lifetime_revenue >= 500 THEN 3
            WHEN lifetime_revenue >= 150 THEN 2
            ELSE 1
        END AS monetary_score
    FROM base
)

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
    first_submitted_order_date,
    most_recent_submitted_order_date,
    days_since_last_order,
    submitted_orders,
    lifetime_orders,
    cancelled_orders,
    refunded_orders,
    lifetime_revenue,
    lifetime_refunded_amount,
    lifetime_net_revenue_after_refunds,
    avg_order_value,
    customer_type,
    recency_segment,
    frequency_segment,
    monetary_segment,
    recency_score,
    frequency_score,
    monetary_score,
    CONCAT(
        CAST(recency_score AS STRING),
        CAST(frequency_score AS STRING),
        CAST(monetary_score AS STRING)
    ) AS rfm_code,
    CASE
        WHEN customer_type = 'no_completed_orders' OR most_recent_order_date IS NULL THEN 'no_completed_orders'

        WHEN recency_segment = 'active_recent'
             AND frequency_segment = 'loyal'
             AND monetary_segment = 'high_value' THEN 'loyal_high_value'

        WHEN recency_segment = 'active_recent'
             AND lifetime_orders >= 2
             AND monetary_segment = 'high_value' THEN 'active_high_value_repeat'

        WHEN recency_segment = 'active_recent'
             AND lifetime_orders >= 2
             AND monetary_segment = 'mid_value' THEN 'active_mid_value_repeat'

        WHEN recency_segment = 'active_recent'
             AND lifetime_orders >= 2
             AND monetary_segment = 'low_value' THEN 'active_low_value_repeat'

        WHEN recency_segment = 'active_recent'
             AND lifetime_orders = 1 THEN 'recent_one_time'

        WHEN recency_segment = 'warm'
             AND lifetime_orders >= 2
             AND monetary_segment = 'high_value' THEN 'warm_high_value_repeat'

        WHEN recency_segment = 'warm'
             AND lifetime_orders >= 2 THEN 'warm_repeat'

        WHEN recency_segment = 'warm'
             AND lifetime_orders = 1 THEN 'warm_one_time'

        WHEN recency_segment = 'cooling_off'
             AND lifetime_orders >= 2
             AND monetary_segment = 'high_value' THEN 'cooling_high_value'

        WHEN recency_segment = 'cooling_off'
             AND lifetime_orders >= 2 THEN 'cooling_repeat'

        WHEN recency_segment = 'cooling_off'
             AND lifetime_orders = 1 THEN 'cooling_one_time'

        WHEN recency_segment = 'lapsed'
             AND monetary_segment = 'high_value' THEN 'lapsed_high_value'

        WHEN recency_segment = 'lapsed'
             AND lifetime_orders >= 2 THEN 'lapsed_repeat'

        WHEN recency_segment = 'lapsed'
             AND lifetime_orders = 1 THEN 'lapsed_one_time'

        ELSE 'other'
    END AS rfm_segment
FROM segmented;
