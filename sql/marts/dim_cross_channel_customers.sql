-- sql/marts/dim_cross_channel_customers.sql
-- Model: marts.dim_cross_channel_customers
-- Grain:
-- One row per cross_channel_customer_key.
--
-- Purpose:
-- Create a conservative cross-channel customer dimension from the explicit
-- customer bridge.
--
-- Notes:
-- - Current Etsy buyer emails are unavailable, so Etsy customers remain unresolved.
-- - Future exact_email bridge rows can roll up into a shared customer key.
-- - This model does not force unresolved identities into false matches.

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.dim_cross_channel_customers` AS

WITH bridge AS (
    SELECT *
    FROM `mischief-made-analytics.marts.cross_channel_customer_bridge`
)

SELECT
    cross_channel_customer_key,

    CASE
        WHEN COUNT(DISTINCT source_channel) > 1
          AND COUNTIF(bridge_resolution_status = 'accepted') > 0
            THEN 'cross_channel_matched'
        WHEN COUNT(DISTINCT source_channel) = 1
          AND COUNTIF(source_channel = 'shopify') > 0
          AND COUNTIF(bridge_resolution_status = 'channel_only') > 0
            THEN 'shopify_channel_only'
        WHEN COUNT(DISTINCT source_channel) = 1
          AND COUNTIF(source_channel = 'etsy') > 0
          AND COUNTIF(bridge_resolution_status = 'unresolved') > 0
            THEN 'etsy_unresolved'
        ELSE 'review'
    END AS customer_identity_status,

    ARRAY_TO_STRING(
        ARRAY_AGG(DISTINCT source_channel ORDER BY source_channel),
        ', '
    ) AS source_channels_present,

    COUNT(*) AS bridge_row_count,
    COUNT(DISTINCT source_channel) AS source_channel_count,

    COUNTIF(source_channel = 'shopify') AS shopify_customer_count,
    COUNTIF(source_channel = 'etsy') AS etsy_buyer_count,

    COUNTIF(bridge_resolution_status = 'accepted') AS accepted_bridge_row_count,
    COUNTIF(bridge_resolution_status = 'channel_only') AS channel_only_bridge_row_count,
    COUNTIF(bridge_resolution_status = 'unresolved') AS unresolved_bridge_row_count,

    ARRAY_TO_STRING(
        ARRAY_AGG(DISTINCT match_type ORDER BY match_type),
        ', '
    ) AS match_types_present,

    MAX(match_confidence) AS max_match_confidence,

    MAX(IF(source_channel = 'shopify', source_customer_key, NULL)) AS shopify_customer_email,
    MAX(IF(source_channel = 'shopify', source_customer_id, NULL)) AS shopify_customer_id,

    MAX(IF(source_channel = 'etsy', source_customer_id, NULL)) AS etsy_buyer_user_id,
    MAX(IF(source_channel = 'etsy', source_customer_key, NULL)) AS etsy_buyer_key,

    COALESCE(
        MAX(IF(source_channel = 'shopify', source_customer_email, NULL)),
        MAX(IF(source_channel = 'etsy', source_customer_email, NULL))
    ) AS best_available_customer_email,

    ARRAY_AGG(source_first_name IGNORE NULLS ORDER BY last_order_at DESC LIMIT 1)[SAFE_OFFSET(0)] AS latest_first_name,
    ARRAY_AGG(source_last_name IGNORE NULLS ORDER BY last_order_at DESC LIMIT 1)[SAFE_OFFSET(0)] AS latest_last_name,

    ARRAY_AGG(source_city IGNORE NULLS ORDER BY last_order_at DESC LIMIT 1)[SAFE_OFFSET(0)] AS latest_city,
    ARRAY_AGG(source_region IGNORE NULLS ORDER BY last_order_at DESC LIMIT 1)[SAFE_OFFSET(0)] AS latest_region,
    ARRAY_AGG(source_country_code IGNORE NULLS ORDER BY last_order_at DESC LIMIT 1)[SAFE_OFFSET(0)] AS latest_country_code,
    ARRAY_AGG(source_postal_code IGNORE NULLS ORDER BY last_order_at DESC LIMIT 1)[SAFE_OFFSET(0)] AS latest_postal_code,

    MIN(first_order_at) AS first_order_at,
    MAX(last_order_at) AS last_order_at,

    SUM(COALESCE(lifetime_order_count, 0)) AS lifetime_order_count,
    SUM(COALESCE(lifetime_items_purchased, 0)) AS lifetime_items_purchased,

    ROUND(SUM(COALESCE(lifetime_gross_revenue, 0)), 2) AS lifetime_gross_revenue,
    ROUND(SUM(COALESCE(lifetime_payment_fee_amount, 0)), 2) AS lifetime_payment_fee_amount,
    ROUND(SUM(COALESCE(lifetime_payment_net_amount, 0)), 2) AS lifetime_payment_net_amount,

    SUM(
        IF(source_channel = 'shopify', COALESCE(lifetime_order_count, 0), 0)
    ) AS shopify_lifetime_order_count,

    ROUND(
        SUM(IF(source_channel = 'shopify', COALESCE(lifetime_gross_revenue, 0), 0)),
        2
    ) AS shopify_lifetime_gross_revenue,

    SUM(
        IF(source_channel = 'etsy', COALESCE(lifetime_order_count, 0), 0)
    ) AS etsy_lifetime_order_count,

    SUM(
        IF(source_channel = 'etsy', COALESCE(lifetime_items_purchased, 0), 0)
    ) AS etsy_lifetime_items_purchased,

    ROUND(
        SUM(IF(source_channel = 'etsy', COALESCE(lifetime_gross_revenue, 0), 0)),
        2
    ) AS etsy_lifetime_gross_revenue,

    ROUND(
        SUM(IF(source_channel = 'etsy', COALESCE(lifetime_payment_fee_amount, 0), 0)),
        2
    ) AS etsy_lifetime_payment_fee_amount,

    ROUND(
        SUM(IF(source_channel = 'etsy', COALESCE(lifetime_payment_net_amount, 0), 0)),
        2
    ) AS etsy_lifetime_payment_net_amount,

    CASE
        WHEN COUNTIF(accepts_email_marketing IS NOT NULL) = 0 THEN NULL
        ELSE LOGICAL_OR(COALESCE(accepts_email_marketing, FALSE))
    END AS accepts_email_marketing,

    CASE
        WHEN COUNTIF(accepts_sms_marketing IS NOT NULL) = 0 THEN NULL
        ELSE LOGICAL_OR(COALESCE(accepts_sms_marketing, FALSE))
    END AS accepts_sms_marketing,

    CASE
        WHEN COUNTIF(tax_exempt IS NOT NULL) = 0 THEN NULL
        ELSE LOGICAL_OR(COALESCE(tax_exempt, FALSE))
    END AS tax_exempt,

    SUM(COALESCE(orders_with_payment_record, 0)) AS etsy_orders_with_payment_record,
    SUM(COALESCE(orders_missing_payment_record, 0)) AS etsy_orders_missing_payment_record,
    SUM(COALESCE(orders_with_blank_sku_items, 0)) AS etsy_orders_with_blank_sku_items,
    SUM(COALESCE(orders_with_refunds_json, 0)) AS etsy_orders_with_refunds_json,

    ARRAY_AGG(source_customer_type IGNORE NULLS ORDER BY last_order_at DESC LIMIT 1)[SAFE_OFFSET(0)] AS latest_source_customer_type,
    ARRAY_AGG(source_recency_segment IGNORE NULLS ORDER BY last_order_at DESC LIMIT 1)[SAFE_OFFSET(0)] AS latest_source_recency_segment

FROM bridge
GROUP BY
    cross_channel_customer_key;