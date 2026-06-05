-- sql/marts/fct_etsy_orders.sql
-- Model: marts.fct_etsy_orders
-- Grain: one row per Etsy receipt/order
-- Purpose:
-- Etsy-native order fact built from cleaned Etsy staging models.
--
-- Notes:
-- - receipt_id is the Etsy-native order/header key.
-- - buyer_user_id is the practical Etsy-native customer key for now.
-- - Missing payment rows are expected for known Etsy receipt-payment 404s.
-- - Cross-channel customer identity resolution is deferred.

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.fct_etsy_orders` AS

WITH receipts AS (
    SELECT *
    FROM `mischief-made-analytics.staging.stg_etsy_receipts`
),

transaction_rollup AS (
    SELECT
        receipt_id,
        COUNT(DISTINCT transaction_id) AS order_item_count,
        SUM(COALESCE(quantity, 0)) AS total_items,
        ROUND(SUM(COALESCE(item_gross_amount, 0)), 2) AS order_item_gross_amount,
        COUNT(DISTINCT listing_id) AS distinct_listing_count,
        COUNT(DISTINCT product_id) AS distinct_product_count,
        COUNTIF(sku IS NULL OR TRIM(sku) = '') AS blank_sku_item_count
    FROM `mischief-made-analytics.staging.stg_etsy_receipt_transactions`
    GROUP BY receipt_id
),

payment_rollup AS (
    SELECT
        receipt_id,
        COUNT(DISTINCT payment_id) AS payment_count,
        ROUND(SUM(COALESCE(selected_gross_amount, 0)), 2) AS payment_gross_amount,
        ROUND(SUM(COALESCE(selected_fee_amount, 0)), 2) AS payment_fee_amount,
        ROUND(SUM(COALESCE(selected_net_amount, 0)), 2) AS payment_net_amount,
        ROUND(SUM(COALESCE(amount_gross, 0)), 2) AS original_payment_gross_amount,
        ROUND(SUM(COALESCE(amount_fees, 0)), 2) AS original_payment_fee_amount,
        ROUND(SUM(COALESCE(amount_net, 0)), 2) AS original_payment_net_amount,
        ROUND(SUM(COALESCE(adjusted_gross, 0)), 2) AS adjusted_payment_gross_amount,
        ROUND(SUM(COALESCE(adjusted_fees, 0)), 2) AS adjusted_payment_fee_amount,
        ROUND(SUM(COALESCE(adjusted_net, 0)), 2) AS adjusted_payment_net_amount,
        ROUND(SUM(COALESCE(posted_gross, 0)), 2) AS posted_payment_gross_amount,
        ROUND(SUM(COALESCE(posted_fees, 0)), 2) AS posted_payment_fee_amount,
        ROUND(SUM(COALESCE(posted_net, 0)), 2) AS posted_payment_net_amount,
        ARRAY_AGG(DISTINCT payment_status IGNORE NULLS) AS payment_statuses
    FROM `mischief-made-analytics.staging.stg_etsy_receipt_payments`
    GROUP BY receipt_id
)

SELECT
    -- channel and keys
    'etsy' AS channel,
    CONCAT('etsy:', CAST(r.receipt_id AS STRING)) AS cross_channel_order_key,
    r.etsy_receipt_key AS etsy_order_key,
    r.receipt_id,

    -- order identity and status
    r.receipt_type,
    r.receipt_status,
    r.is_paid,
    r.is_shipped,

    -- customer and seller
    r.buyer_user_id,
    r.etsy_buyer_key,
    r.buyer_email,
    r.seller_user_id,

    -- order dates
    r.receipt_created_at AS order_created_at,
    r.receipt_created_date AS order_date,
    r.receipt_updated_at AS order_updated_at,
    r.receipt_updated_date AS order_updated_date,

    -- shipping geography
    r.shipping_city,
    r.shipping_state,
    r.shipping_zip,
    r.shipping_country_iso,

    -- receipt/order amounts
    COALESCE(r.subtotal, 0) AS subtotal_amount,
    COALESCE(r.discount_amt, 0) AS discount_amount,
    COALESCE(r.total_shipping_cost, 0) AS shipping_amount,
    COALESCE(r.total_tax_cost, 0) AS tax_amount,
    COALESCE(r.total_vat_cost, 0) AS vat_amount,
    COALESCE(r.gift_wrap_price, 0) AS gift_wrap_amount,

    COALESCE(
        r.grandtotal,
        r.total_price,
        COALESCE(r.subtotal, 0)
            + COALESCE(r.total_shipping_cost, 0)
            + COALESCE(r.total_tax_cost, 0)
            + COALESCE(r.total_vat_cost, 0)
            + COALESCE(r.gift_wrap_price, 0)
            - COALESCE(r.discount_amt, 0)
    ) AS receipt_gross_amount,

    -- order item rollups
    COALESCE(t.order_item_count, 0) AS order_item_count,
    COALESCE(t.total_items, 0) AS total_items,
    COALESCE(t.order_item_gross_amount, 0) AS order_item_gross_amount,
    COALESCE(t.distinct_listing_count, 0) AS distinct_listing_count,
    COALESCE(t.distinct_product_count, 0) AS distinct_product_count,
    COALESCE(t.blank_sku_item_count, 0) AS blank_sku_item_count,

    -- payment rollups
    COALESCE(p.payment_count, 0) AS payment_count,
    p.payment_statuses,
    COALESCE(p.payment_gross_amount, 0) AS payment_gross_amount,
    COALESCE(p.payment_fee_amount, 0) AS payment_fee_amount,
    COALESCE(p.payment_net_amount, 0) AS payment_net_amount,
    COALESCE(p.original_payment_gross_amount, 0) AS original_payment_gross_amount,
    COALESCE(p.original_payment_fee_amount, 0) AS original_payment_fee_amount,
    COALESCE(p.original_payment_net_amount, 0) AS original_payment_net_amount,
    COALESCE(p.adjusted_payment_gross_amount, 0) AS adjusted_payment_gross_amount,
    COALESCE(p.adjusted_payment_fee_amount, 0) AS adjusted_payment_fee_amount,
    COALESCE(p.adjusted_payment_net_amount, 0) AS adjusted_payment_net_amount,
    COALESCE(p.posted_payment_gross_amount, 0) AS posted_payment_gross_amount,
    COALESCE(p.posted_payment_fee_amount, 0) AS posted_payment_fee_amount,
    COALESCE(p.posted_payment_net_amount, 0) AS posted_payment_net_amount,

    -- practical flags
    p.receipt_id IS NOT NULL AS has_payment_record,
    p.receipt_id IS NULL AS missing_payment_record,
    COALESCE(t.blank_sku_item_count, 0) > 0 AS has_blank_sku,
    r.refunds_json IS NOT NULL AND r.refunds_json != '[]' AS has_refunds_json,

    -- source metadata
    r.landing_run_id,
    r.landing_loaded_at

FROM receipts AS r
LEFT JOIN transaction_rollup AS t
    ON r.receipt_id = t.receipt_id
LEFT JOIN payment_rollup AS p
    ON r.receipt_id = p.receipt_id;