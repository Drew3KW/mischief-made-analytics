-- sql/analysis/cross_channel_customer_overlap_audit.sql
-- Purpose:
-- Audit conservative cross-channel customer match candidates across Shopify and Etsy.
--
-- Grain:
-- One row per customer audit candidate or unresolved source customer.
--
-- Notes:
-- - This is an audit view, not the final bridge model.
-- - exact_email is the only automated customer match candidate in this pass.
-- - Unmatched and unresolved customers remain visible by design.

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_cross_channel_customer_overlap_audit` AS

WITH shopify_customers AS (
    SELECT
        LOWER(TRIM(customer_email)) AS shopify_customer_email,
        CAST(shopify_customer_id AS STRING) AS shopify_customer_id,
        first_name AS shopify_first_name,
        last_name AS shopify_last_name,
        first_order_at AS shopify_first_order_at,
        last_order_at AS shopify_last_order_at,
        lifetime_order_count_from_orders AS shopify_lifetime_order_count,
        default_address_city AS shopify_city,
        default_address_province_code AS shopify_province_code,
        default_address_country_code AS shopify_country_code
    FROM `mischief-made-analytics.marts.dim_customers`
    WHERE customer_email IS NOT NULL
      AND TRIM(customer_email) != ''
),

etsy_customers AS (
    SELECT
        CAST(buyer_user_id AS STRING) AS buyer_user_id,
        etsy_buyer_key,
        LOWER(TRIM(latest_buyer_email)) AS etsy_customer_email,
        first_order_at AS etsy_first_order_at,
        last_order_at AS etsy_last_order_at,
        lifetime_order_count AS etsy_lifetime_order_count,
        latest_shipping_city AS etsy_city,
        latest_shipping_state AS etsy_state,
        latest_shipping_country_iso AS etsy_country_iso
    FROM `mischief-made-analytics.marts.dim_etsy_customers`
),

exact_email_matches AS (
    SELECT
        'candidate' AS audit_row_type,
        'exact_email' AS audit_match_type,
        'matched_candidate' AS audit_resolution_status,
        1.00 AS match_confidence,
        CONCAT('customer_email:', s.shopify_customer_email) AS cross_channel_customer_candidate_key,

        s.shopify_customer_email,
        s.shopify_customer_id,
        s.shopify_first_name,
        s.shopify_last_name,
        s.shopify_first_order_at,
        s.shopify_last_order_at,
        s.shopify_lifetime_order_count,
        s.shopify_city,
        s.shopify_province_code,
        s.shopify_country_code,

        e.buyer_user_id,
        e.etsy_buyer_key,
        e.etsy_customer_email,
        e.etsy_first_order_at,
        e.etsy_last_order_at,
        e.etsy_lifetime_order_count,
        e.etsy_city,
        e.etsy_state,
        e.etsy_country_iso,

        COUNT(*) OVER (
            PARTITION BY s.shopify_customer_email
        ) AS etsy_buyers_for_shopify_email,

        COUNT(*) OVER (
            PARTITION BY e.buyer_user_id
        ) AS shopify_customers_for_etsy_buyer
    FROM shopify_customers AS s
    INNER JOIN etsy_customers AS e
        ON s.shopify_customer_email = e.etsy_customer_email
    WHERE e.etsy_customer_email IS NOT NULL
      AND e.etsy_customer_email != ''
),

shopify_only_customers AS (
    SELECT
        'source_only' AS audit_row_type,
        'channel_only' AS audit_match_type,
        'shopify_only_no_exact_email_match' AS audit_resolution_status,
        CAST(NULL AS FLOAT64) AS match_confidence,
        CONCAT('shopify:', s.shopify_customer_email) AS cross_channel_customer_candidate_key,

        s.shopify_customer_email,
        s.shopify_customer_id,
        s.shopify_first_name,
        s.shopify_last_name,
        s.shopify_first_order_at,
        s.shopify_last_order_at,
        s.shopify_lifetime_order_count,
        s.shopify_city,
        s.shopify_province_code,
        s.shopify_country_code,

        CAST(NULL AS STRING) AS buyer_user_id,
        CAST(NULL AS STRING) AS etsy_buyer_key,
        CAST(NULL AS STRING) AS etsy_customer_email,
        CAST(NULL AS TIMESTAMP) AS etsy_first_order_at,
        CAST(NULL AS TIMESTAMP) AS etsy_last_order_at,
        CAST(NULL AS INT64) AS etsy_lifetime_order_count,
        CAST(NULL AS STRING) AS etsy_city,
        CAST(NULL AS STRING) AS etsy_state,
        CAST(NULL AS STRING) AS etsy_country_iso,

        CAST(NULL AS INT64) AS etsy_buyers_for_shopify_email,
        CAST(NULL AS INT64) AS shopify_customers_for_etsy_buyer
    FROM shopify_customers AS s
    WHERE NOT EXISTS (
        SELECT 1
        FROM etsy_customers AS e
        WHERE e.etsy_customer_email = s.shopify_customer_email
    )
),

etsy_email_only_customers AS (
    SELECT
        'source_only' AS audit_row_type,
        'channel_only' AS audit_match_type,
        'etsy_only_email_no_exact_shopify_match' AS audit_resolution_status,
        CAST(NULL AS FLOAT64) AS match_confidence,
        CONCAT('etsy:', e.buyer_user_id) AS cross_channel_customer_candidate_key,

        CAST(NULL AS STRING) AS shopify_customer_email,
        CAST(NULL AS STRING) AS shopify_customer_id,
        CAST(NULL AS STRING) AS shopify_first_name,
        CAST(NULL AS STRING) AS shopify_last_name,
        CAST(NULL AS TIMESTAMP) AS shopify_first_order_at,
        CAST(NULL AS TIMESTAMP) AS shopify_last_order_at,
        CAST(NULL AS INT64) AS shopify_lifetime_order_count,
        CAST(NULL AS STRING) AS shopify_city,
        CAST(NULL AS STRING) AS shopify_province_code,
        CAST(NULL AS STRING) AS shopify_country_code,

        e.buyer_user_id,
        e.etsy_buyer_key,
        e.etsy_customer_email,
        e.etsy_first_order_at,
        e.etsy_last_order_at,
        e.etsy_lifetime_order_count,
        e.etsy_city,
        e.etsy_state,
        e.etsy_country_iso,

        CAST(NULL AS INT64) AS etsy_buyers_for_shopify_email,
        CAST(NULL AS INT64) AS shopify_customers_for_etsy_buyer
    FROM etsy_customers AS e
    WHERE e.etsy_customer_email IS NOT NULL
      AND e.etsy_customer_email != ''
      AND NOT EXISTS (
          SELECT 1
          FROM shopify_customers AS s
          WHERE s.shopify_customer_email = e.etsy_customer_email
      )
),

etsy_unresolved_no_email_customers AS (
    SELECT
        'unresolved' AS audit_row_type,
        'unresolved' AS audit_match_type,
        'etsy_buyer_without_email' AS audit_resolution_status,
        CAST(NULL AS FLOAT64) AS match_confidence,
        CONCAT('etsy:', e.buyer_user_id) AS cross_channel_customer_candidate_key,

        CAST(NULL AS STRING) AS shopify_customer_email,
        CAST(NULL AS STRING) AS shopify_customer_id,
        CAST(NULL AS STRING) AS shopify_first_name,
        CAST(NULL AS STRING) AS shopify_last_name,
        CAST(NULL AS TIMESTAMP) AS shopify_first_order_at,
        CAST(NULL AS TIMESTAMP) AS shopify_last_order_at,
        CAST(NULL AS INT64) AS shopify_lifetime_order_count,
        CAST(NULL AS STRING) AS shopify_city,
        CAST(NULL AS STRING) AS shopify_province_code,
        CAST(NULL AS STRING) AS shopify_country_code,

        e.buyer_user_id,
        e.etsy_buyer_key,
        e.etsy_customer_email,
        e.etsy_first_order_at,
        e.etsy_last_order_at,
        e.etsy_lifetime_order_count,
        e.etsy_city,
        e.etsy_state,
        e.etsy_country_iso,

        CAST(NULL AS INT64) AS etsy_buyers_for_shopify_email,
        CAST(NULL AS INT64) AS shopify_customers_for_etsy_buyer
    FROM etsy_customers AS e
    WHERE e.etsy_customer_email IS NULL
       OR e.etsy_customer_email = ''
)

SELECT * FROM exact_email_matches
UNION ALL
SELECT * FROM shopify_only_customers
UNION ALL
SELECT * FROM etsy_email_only_customers
UNION ALL
SELECT * FROM etsy_unresolved_no_email_customers;