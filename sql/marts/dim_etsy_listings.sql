-- sql/marts/dim_etsy_listings.sql
-- Model: marts.dim_etsy_listings
-- Grain: one row per Etsy listing_id
-- Purpose:
-- Etsy-native listing dimension built from Etsy order-item facts.
--
-- Notes:
-- - listing_id is the practical Etsy-native product/listing key for now.
-- - Some order items have blank SKUs.
-- - Cross-channel product-family harmonization is deferred.

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.dim_etsy_listings` AS

WITH order_items AS (
    SELECT *
    FROM `mischief-made-analytics.marts.fct_etsy_order_items`
    WHERE listing_id IS NOT NULL
),

listing_rollup AS (
    SELECT
        listing_id,
        etsy_listing_key,

        ARRAY_AGG(
            listing_title IGNORE NULLS
            ORDER BY order_date DESC, transaction_created_at DESC
            LIMIT 1
        )[SAFE_OFFSET(0)] AS latest_listing_title,

        ARRAY_AGG(
            listing_description IGNORE NULLS
            ORDER BY order_date DESC, transaction_created_at DESC
            LIMIT 1
        )[SAFE_OFFSET(0)] AS latest_listing_description,

        ARRAY_AGG(
            sku IGNORE NULLS
            ORDER BY order_date DESC, transaction_created_at DESC
            LIMIT 1
        )[SAFE_OFFSET(0)] AS latest_sku,

        COUNT(DISTINCT product_id) AS observed_product_id_count,
        COUNT(DISTINCT sku) AS observed_sku_count,
        COUNT(DISTINCT receipt_id) AS lifetime_order_count,
        COUNT(DISTINCT transaction_id) AS lifetime_order_item_count,

        SUM(COALESCE(quantity, 0)) AS lifetime_units_sold,
        ROUND(SUM(COALESCE(item_gross_amount, 0)), 2) AS lifetime_item_gross_revenue,

        MIN(order_date) AS first_sold_date,
        MAX(order_date) AS last_sold_date,

        COUNTIF(has_blank_sku) AS blank_sku_order_item_count,
        COUNTIF(is_digital) AS digital_order_item_count,

        ARRAY_AGG(
            DISTINCT product_id IGNORE NULLS
            LIMIT 20
        ) AS observed_product_ids,

        ARRAY_AGG(
            DISTINCT sku IGNORE NULLS
            LIMIT 20
        ) AS observed_skus

    FROM order_items
    GROUP BY
        listing_id,
        etsy_listing_key
)

SELECT
    listing_id,
    etsy_listing_key,
    latest_listing_title,
    latest_listing_description,
    latest_sku,

    observed_product_id_count,
    observed_sku_count,
    observed_product_ids,
    observed_skus,

    lifetime_order_count,
    lifetime_order_item_count,
    lifetime_units_sold,
    lifetime_item_gross_revenue,

    first_sold_date,
    last_sold_date,

    blank_sku_order_item_count,
    digital_order_item_count,

    CASE
        WHEN last_sold_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) THEN 'active_recent'
        WHEN last_sold_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY) THEN 'warm'
        WHEN last_sold_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY) THEN 'cooling_off'
        ELSE 'lapsed'
    END AS etsy_listing_recency_segment

FROM listing_rollup;