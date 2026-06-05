-- sql/marts/dim_etsy_customers.sql
-- Model: marts.dim_etsy_customers
-- Grain: one row per Etsy buyer_user_id
-- Purpose:
-- Etsy-native customer dimension built from Etsy order facts.
--
-- Notes:
-- - buyer_user_id is the practical Etsy-native customer key.
-- - buyer_email may be null in Etsy source data.
-- - Cross-channel customer identity resolution is deferred.

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.dim_etsy_customers` AS

WITH orders AS (
    SELECT *
    FROM `mischief-made-analytics.marts.fct_etsy_orders`
    WHERE buyer_user_id IS NOT NULL
),

customer_rollup AS (
    SELECT
        buyer_user_id,
        etsy_buyer_key,

        ARRAY_AGG(
            buyer_email IGNORE NULLS
            ORDER BY order_created_at DESC
            LIMIT 1
        )[SAFE_OFFSET(0)] AS latest_buyer_email,

        MIN(order_created_at) AS first_order_at,
        DATE(MIN(order_created_at)) AS first_order_date,
        MAX(order_created_at) AS last_order_at,
        DATE(MAX(order_created_at)) AS last_order_date,

        COUNT(DISTINCT receipt_id) AS lifetime_order_count,
        SUM(COALESCE(total_items, 0)) AS lifetime_items_purchased,

        ROUND(SUM(COALESCE(receipt_gross_amount, 0)), 2) AS lifetime_gross_revenue,
        ROUND(SUM(COALESCE(payment_fee_amount, 0)), 2) AS lifetime_payment_fee_amount,
        ROUND(SUM(COALESCE(payment_net_amount, 0)), 2) AS lifetime_payment_net_amount,

        COUNTIF(has_payment_record) AS orders_with_payment_record,
        COUNTIF(missing_payment_record) AS orders_missing_payment_record,
        COUNTIF(has_blank_sku) AS orders_with_blank_sku_items,
        COUNTIF(has_refunds_json) AS orders_with_refunds_json,

        ARRAY_AGG(
            shipping_country_iso IGNORE NULLS
            ORDER BY order_created_at DESC
            LIMIT 1
        )[SAFE_OFFSET(0)] AS latest_shipping_country_iso,

        ARRAY_AGG(
            shipping_state IGNORE NULLS
            ORDER BY order_created_at DESC
            LIMIT 1
        )[SAFE_OFFSET(0)] AS latest_shipping_state,

        ARRAY_AGG(
            shipping_city IGNORE NULLS
            ORDER BY order_created_at DESC
            LIMIT 1
        )[SAFE_OFFSET(0)] AS latest_shipping_city

    FROM orders
    GROUP BY
        buyer_user_id,
        etsy_buyer_key
)

SELECT
    buyer_user_id,
    etsy_buyer_key,
    latest_buyer_email,

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

    CASE
        WHEN lifetime_order_count >= 5 THEN 'loyal'
        WHEN lifetime_order_count >= 2 THEN 'repeat'
        ELSE 'one_time'
    END AS etsy_customer_type,

    CASE
        WHEN last_order_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) THEN 'active_recent'
        WHEN last_order_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY) THEN 'warm'
        WHEN last_order_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY) THEN 'cooling_off'
        ELSE 'lapsed'
    END AS etsy_recency_segment

FROM customer_rollup;