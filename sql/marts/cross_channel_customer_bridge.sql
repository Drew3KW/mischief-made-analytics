-- sql/marts/cross_channel_customer_bridge.sql
-- Model: marts.cross_channel_customer_bridge
-- Grain:
-- - One row per Shopify customer.
-- - One row per Etsy buyer.
--
-- Purpose:
-- Create a conservative, auditable bridge for cross-channel customer identity.
--
-- Notes:
-- - Shopify customers map to customer_email when available.
-- - Etsy buyers map to buyer_user_id.
-- - exact_email matching is supported for future Etsy buyer email availability.
-- - Current Etsy buyer emails are returned as null, so Etsy buyers remain unresolved.
-- - Unresolved identities remain visible by design.

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.cross_channel_customer_bridge` AS

WITH shopify_customers AS (
    SELECT
        LOWER(TRIM(customer_email)) AS customer_email,
        CAST(shopify_customer_id AS STRING) AS shopify_customer_id,
        first_name,
        last_name,
        accepts_email_marketing,
        accepts_sms_marketing,
        total_orders,
        total_spent,
        tax_exempt,
        default_address_city,
        default_address_province_code,
        default_address_country_code,
        default_address_zip,
        first_order_at,
        last_order_at,
        lifetime_order_count_from_orders
    FROM `mischief-made-analytics.marts.dim_customers`
    WHERE customer_email IS NOT NULL
      AND TRIM(customer_email) != ''
),

etsy_customers AS (
    SELECT
        CAST(buyer_user_id AS STRING) AS buyer_user_id,
        etsy_buyer_key,
        LOWER(TRIM(latest_buyer_email)) AS latest_buyer_email,
        first_order_at,
        first_order_date,
        last_order_at,
        last_order_date,
        lifetime_order_count,
        lifetime_items_purchased,
        lifetime_gross_revenue,
        lifetime_payment_fee_amount,
        lifetime_payment_net_amount,
        orders_with_payment_record,
        orders_missing_payment_record,
        orders_with_blank_sku_items,
        orders_with_refunds_json,
        latest_shipping_country_iso,
        latest_shipping_state,
        latest_shipping_city,
        etsy_customer_type,
        etsy_recency_segment
    FROM `mischief-made-analytics.marts.dim_etsy_customers`
    WHERE buyer_user_id IS NOT NULL
),

shopify_bridge AS (
    SELECT
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM etsy_customers AS e
                WHERE e.latest_buyer_email = s.customer_email
            )
                THEN CONCAT('customer_email:', s.customer_email)
            ELSE CONCAT('shopify:', s.customer_email)
        END AS cross_channel_customer_key,

        'shopify' AS source_channel,
        'shopify_customer' AS source_entity_type,
        s.customer_email AS source_customer_key,
        s.shopify_customer_id AS source_customer_id,
        s.customer_email AS source_customer_email,

        s.first_name AS source_first_name,
        s.last_name AS source_last_name,
        s.default_address_city AS source_city,
        s.default_address_province_code AS source_region,
        s.default_address_country_code AS source_country_code,
        s.default_address_zip AS source_postal_code,

        CASE
            WHEN EXISTS (
                SELECT 1
                FROM etsy_customers AS e
                WHERE e.latest_buyer_email = s.customer_email
            )
                THEN 'exact_email'
            ELSE 'channel_only'
        END AS match_type,

        CASE
            WHEN EXISTS (
                SELECT 1
                FROM etsy_customers AS e
                WHERE e.latest_buyer_email = s.customer_email
            )
                THEN 'accepted'
            ELSE 'channel_only'
        END AS bridge_resolution_status,

        CASE
            WHEN EXISTS (
                SELECT 1
                FROM etsy_customers AS e
                WHERE e.latest_buyer_email = s.customer_email
            )
                THEN 1.00
            ELSE NULL
        END AS match_confidence,

        s.first_order_at,
        s.last_order_at,
        s.lifetime_order_count_from_orders AS lifetime_order_count,
        CAST(NULL AS INT64) AS lifetime_items_purchased,
        SAFE_CAST(s.total_spent AS NUMERIC) AS lifetime_gross_revenue,
        CAST(NULL AS NUMERIC) AS lifetime_payment_fee_amount,
        CAST(NULL AS NUMERIC) AS lifetime_payment_net_amount,

CASE
    WHEN LOWER(CAST(s.accepts_email_marketing AS STRING)) IN ('true', 'yes', '1', 'y') THEN TRUE
    WHEN LOWER(CAST(s.accepts_email_marketing AS STRING)) IN ('false', 'no', '0', 'n') THEN FALSE
    ELSE NULL
END AS accepts_email_marketing,

CASE
    WHEN LOWER(CAST(s.accepts_sms_marketing AS STRING)) IN ('true', 'yes', '1', 'y') THEN TRUE
    WHEN LOWER(CAST(s.accepts_sms_marketing AS STRING)) IN ('false', 'no', '0', 'n') THEN FALSE
    ELSE NULL
END AS accepts_sms_marketing,

CASE
    WHEN LOWER(CAST(s.tax_exempt AS STRING)) IN ('true', 'yes', '1', 'y') THEN TRUE
    WHEN LOWER(CAST(s.tax_exempt AS STRING)) IN ('false', 'no', '0', 'n') THEN FALSE
    ELSE NULL
END AS tax_exempt,

        CAST(NULL AS INT64) AS orders_with_payment_record,
        CAST(NULL AS INT64) AS orders_missing_payment_record,
        CAST(NULL AS INT64) AS orders_with_blank_sku_items,
        CAST(NULL AS INT64) AS orders_with_refunds_json,
        CAST(NULL AS STRING) AS source_customer_type,
        CAST(NULL AS STRING) AS source_recency_segment
    FROM shopify_customers AS s
),

etsy_bridge AS (
    SELECT
        CASE
            WHEN e.latest_buyer_email IS NOT NULL
              AND e.latest_buyer_email != ''
              AND EXISTS (
                  SELECT 1
                  FROM shopify_customers AS s
                  WHERE s.customer_email = e.latest_buyer_email
              )
                THEN CONCAT('customer_email:', e.latest_buyer_email)
            ELSE CONCAT('etsy:', e.buyer_user_id)
        END AS cross_channel_customer_key,

        'etsy' AS source_channel,
        'etsy_buyer' AS source_entity_type,
        e.etsy_buyer_key AS source_customer_key,
        e.buyer_user_id AS source_customer_id,
        e.latest_buyer_email AS source_customer_email,

        CAST(NULL AS STRING) AS source_first_name,
        CAST(NULL AS STRING) AS source_last_name,
        e.latest_shipping_city AS source_city,
        e.latest_shipping_state AS source_region,
        e.latest_shipping_country_iso AS source_country_code,
        CAST(NULL AS STRING) AS source_postal_code,

        CASE
            WHEN e.latest_buyer_email IS NOT NULL
              AND e.latest_buyer_email != ''
              AND EXISTS (
                  SELECT 1
                  FROM shopify_customers AS s
                  WHERE s.customer_email = e.latest_buyer_email
              )
                THEN 'exact_email'
            WHEN e.latest_buyer_email IS NULL
              OR e.latest_buyer_email = ''
                THEN 'unresolved'
            ELSE 'channel_only'
        END AS match_type,

        CASE
            WHEN e.latest_buyer_email IS NOT NULL
              AND e.latest_buyer_email != ''
              AND EXISTS (
                  SELECT 1
                  FROM shopify_customers AS s
                  WHERE s.customer_email = e.latest_buyer_email
              )
                THEN 'accepted'
            WHEN e.latest_buyer_email IS NULL
              OR e.latest_buyer_email = ''
                THEN 'unresolved'
            ELSE 'channel_only'
        END AS bridge_resolution_status,

        CASE
            WHEN e.latest_buyer_email IS NOT NULL
              AND e.latest_buyer_email != ''
              AND EXISTS (
                  SELECT 1
                  FROM shopify_customers AS s
                  WHERE s.customer_email = e.latest_buyer_email
              )
                THEN 1.00
            ELSE NULL
        END AS match_confidence,

        e.first_order_at,
        e.last_order_at,
        e.lifetime_order_count,
        e.lifetime_items_purchased,
        SAFE_CAST(e.lifetime_gross_revenue AS NUMERIC) AS lifetime_gross_revenue,
        SAFE_CAST(e.lifetime_payment_fee_amount AS NUMERIC) AS lifetime_payment_fee_amount,
        SAFE_CAST(e.lifetime_payment_net_amount AS NUMERIC) AS lifetime_payment_net_amount,

        CAST(NULL AS BOOL) AS accepts_email_marketing,
        CAST(NULL AS BOOL) AS accepts_sms_marketing,
        CAST(NULL AS BOOL) AS tax_exempt,

        e.orders_with_payment_record,
        e.orders_missing_payment_record,
        e.orders_with_blank_sku_items,
        e.orders_with_refunds_json,
        e.etsy_customer_type AS source_customer_type,
        e.etsy_recency_segment AS source_recency_segment
    FROM etsy_customers AS e
)

SELECT * FROM shopify_bridge
UNION ALL
SELECT * FROM etsy_bridge;