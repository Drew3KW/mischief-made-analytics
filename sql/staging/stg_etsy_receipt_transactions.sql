-- sql/staging/stg_etsy_receipt_transactions.sql
-- Model: staging.stg_etsy_receipt_transactions
-- Grain: one row per Etsy receipt transaction
-- Purpose: cleaned and typed Etsy order-item staging model
-- Notes:
-- - Etsy transaction_id is the native Etsy order-item key.
-- - Some Etsy transaction rows may have blank SKUs.
-- - Product-family harmonization is deferred.

CREATE OR REPLACE TABLE `mischief-made-analytics.staging.stg_etsy_receipt_transactions` AS

WITH source AS (
    SELECT *
    FROM `mischief-made-analytics.raw_load.etsy_receipt_transactions_api_latest`
),

deduped AS (
    SELECT * EXCEPT(row_number)
    FROM (
        SELECT
            source.*,
            ROW_NUMBER() OVER (
                PARTITION BY transaction_id
                ORDER BY
                    COALESCE(created_timestamp, create_timestamp) DESC,
                    landing_loaded_at DESC
            ) AS row_number
        FROM source
    )
    WHERE row_number = 1
)

SELECT
    -- landing metadata
    landing_run_id,
    landing_loaded_at,

    -- keys
    transaction_id,
    CAST(transaction_id AS STRING) AS etsy_transaction_key,
    receipt_id,
    CAST(receipt_id AS STRING) AS etsy_receipt_key,
    NULLIF(TRIM(transaction_type), '') AS transaction_type,

    -- customer and seller identifiers
    buyer_user_id,
    CAST(buyer_user_id AS STRING) AS etsy_buyer_key,
    seller_user_id,

    -- listing and product identifiers
    listing_id,
    CAST(listing_id AS STRING) AS etsy_listing_key,
    listing_image_id,
    product_id,
    CAST(product_id AS STRING) AS etsy_product_key,
    NULLIF(TRIM(sku), '') AS sku,
    NULLIF(TRIM(title), '') AS listing_title,
    NULLIF(TRIM(description), '') AS listing_description,

    -- quantities and item flags
    quantity,
    is_digital,

    -- timestamps
    create_timestamp,
    created_timestamp,
    paid_timestamp,
    shipped_timestamp,
    expected_ship_date AS expected_ship_timestamp,
    TIMESTAMP_SECONDS(COALESCE(created_timestamp, create_timestamp)) AS transaction_created_at,
    DATE(TIMESTAMP_SECONDS(COALESCE(created_timestamp, create_timestamp))) AS transaction_created_date,
    TIMESTAMP_SECONDS(paid_timestamp) AS paid_at,
    DATE(TIMESTAMP_SECONDS(paid_timestamp)) AS paid_date,
    TIMESTAMP_SECONDS(shipped_timestamp) AS shipped_at,
    DATE(TIMESTAMP_SECONDS(shipped_timestamp)) AS shipped_date,
    TIMESTAMP_SECONDS(expected_ship_date) AS expected_ship_at,
    DATE(TIMESTAMP_SECONDS(expected_ship_date)) AS expected_ship_date,

    -- processing and shipping fields
    min_processing_days,
    max_processing_days,
    NULLIF(TRIM(shipping_method), '') AS shipping_method,
    shipping_profile_id,
    NULLIF(TRIM(shipping_upgrade), '') AS shipping_upgrade,

    -- money fields
    price AS item_price,
    NULLIF(TRIM(price_currency), '') AS item_price_currency,
    shipping_cost,
    NULLIF(TRIM(shipping_cost_currency), '') AS shipping_cost_currency,
    buyer_coupon,
    shop_coupon,

    -- derived item amount
    quantity * price AS item_gross_amount,

    -- json payloads retained for future modeling
    file_data_json,
    product_data_json,
    variations_json,
    raw_json

FROM deduped;