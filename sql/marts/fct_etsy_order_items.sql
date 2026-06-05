-- sql/marts/fct_etsy_order_items.sql
-- Model: marts.fct_etsy_order_items
-- Grain: one row per Etsy receipt transaction
-- Purpose:
-- Etsy-native order-item fact built from staged Etsy receipt transactions.
--
-- Notes:
-- - transaction_id is the Etsy-native order-item key.
-- - Some Etsy order items have blank SKUs.
-- - Cross-channel product-family harmonization is deferred.

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.fct_etsy_order_items` AS

WITH transactions AS (
    SELECT *
    FROM `mischief-made-analytics.staging.stg_etsy_receipt_transactions`
),

receipts AS (
    SELECT
        receipt_id,
        etsy_receipt_key,
        receipt_status,
        is_paid,
        is_shipped,
        receipt_created_at,
        receipt_created_date,
        buyer_user_id,
        etsy_buyer_key,
        buyer_email
    FROM `mischief-made-analytics.staging.stg_etsy_receipts`
)

SELECT
    -- channel and keys
    'etsy' AS channel,
    CONCAT('etsy:', CAST(t.transaction_id AS STRING)) AS cross_channel_order_item_key,
    CONCAT('etsy:', CAST(t.receipt_id AS STRING)) AS cross_channel_order_key,
    t.etsy_transaction_key AS etsy_order_item_key,
    t.etsy_receipt_key AS etsy_order_key,
    t.transaction_id,
    t.receipt_id,

    -- order context
    r.receipt_status,
    r.is_paid,
    r.is_shipped,
    r.receipt_created_at AS order_created_at,
    r.receipt_created_date AS order_date,

    -- transaction dates
    t.transaction_created_at,
    t.transaction_created_date,
    t.paid_at,
    t.paid_date,
    t.shipped_at,
    t.shipped_date,
    t.expected_ship_at,
    t.expected_ship_date,

    -- customer and seller
    COALESCE(t.buyer_user_id, r.buyer_user_id) AS buyer_user_id,
    COALESCE(t.etsy_buyer_key, r.etsy_buyer_key) AS etsy_buyer_key,
    r.buyer_email,
    t.seller_user_id,

    -- listing and product identifiers
    t.listing_id,
    t.etsy_listing_key,
    t.listing_image_id,
    t.product_id,
    t.etsy_product_key,
    t.sku,
    t.listing_title,
    t.listing_description,

    -- item fields
    t.transaction_type,
    COALESCE(t.quantity, 0) AS quantity,
    t.is_digital,
    t.min_processing_days,
    t.max_processing_days,
    t.shipping_method,
    t.shipping_profile_id,
    t.shipping_upgrade,

    -- money fields
    COALESCE(t.item_price, 0) AS item_price,
    t.item_price_currency,
    COALESCE(t.shipping_cost, 0) AS shipping_cost,
    t.shipping_cost_currency,
    COALESCE(t.buyer_coupon, 0) AS buyer_coupon_amount,
    COALESCE(t.shop_coupon, 0) AS shop_coupon_amount,
    COALESCE(t.item_gross_amount, 0) AS item_gross_amount,

    -- practical flags
    t.sku IS NULL OR TRIM(t.sku) = '' AS has_blank_sku,
    r.receipt_id IS NULL AS missing_receipt_record,

    -- source metadata
    t.landing_run_id,
    t.landing_loaded_at

FROM transactions AS t
LEFT JOIN receipts AS r
    ON t.receipt_id = r.receipt_id;