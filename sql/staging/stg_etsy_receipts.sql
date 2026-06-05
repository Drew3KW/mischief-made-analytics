-- sql/staging/stg_etsy_receipts.sql
-- Model: staging.stg_etsy_receipts
-- Grain: one row per Etsy receipt
-- Purpose: cleaned and typed Etsy receipt/order-header staging model
-- Notes:
-- - Etsy receipt_id is the native Etsy order/header key.
-- - buyer_user_id is the practical Etsy-native customer key for now.
-- - Cross-channel customer identity resolution is deferred.

CREATE OR REPLACE TABLE `mischief-made-analytics.staging.stg_etsy_receipts` AS

WITH source AS (
    SELECT *
    FROM `mischief-made-analytics.raw_load.etsy_receipts_api_latest`
),

deduped AS (
    SELECT * EXCEPT(row_number)
    FROM (
        SELECT
            source.*,
            ROW_NUMBER() OVER (
                PARTITION BY receipt_id
                ORDER BY
                    COALESCE(updated_timestamp, update_timestamp, created_timestamp, create_timestamp) DESC,
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
    receipt_id,
    CAST(receipt_id AS STRING) AS etsy_receipt_key,
    receipt_type,

    -- status flags
    TRIM(status) AS receipt_status,
    is_paid,
    is_shipped,

    -- customer and seller identifiers
    buyer_user_id,
    CAST(buyer_user_id AS STRING) AS etsy_buyer_key,
    LOWER(NULLIF(TRIM(buyer_email), '')) AS buyer_email,
    seller_user_id,
    LOWER(NULLIF(TRIM(seller_email), '')) AS seller_email,
    LOWER(NULLIF(TRIM(payment_email), '')) AS payment_email,
    NULLIF(TRIM(payment_method), '') AS payment_method,

    -- timestamps
    create_timestamp,
    created_timestamp,
    update_timestamp,
    updated_timestamp,
    TIMESTAMP_SECONDS(COALESCE(created_timestamp, create_timestamp)) AS receipt_created_at,
    DATE(TIMESTAMP_SECONDS(COALESCE(created_timestamp, create_timestamp))) AS receipt_created_date,
    TIMESTAMP_SECONDS(COALESCE(updated_timestamp, update_timestamp)) AS receipt_updated_at,
    DATE(TIMESTAMP_SECONDS(COALESCE(updated_timestamp, update_timestamp))) AS receipt_updated_date,

    -- shipping and address fields
    NULLIF(TRIM(name), '') AS ship_to_name,
    NULLIF(TRIM(first_line), '') AS shipping_address_line_1,
    NULLIF(TRIM(second_line), '') AS shipping_address_line_2,
    NULLIF(TRIM(city), '') AS shipping_city,
    NULLIF(TRIM(state), '') AS shipping_state,
    NULLIF(TRIM(zip), '') AS shipping_zip,
    NULLIF(TRIM(country_iso), '') AS shipping_country_iso,
    NULLIF(TRIM(formatted_address), '') AS formatted_shipping_address,

    -- gift and message fields
    is_gift,
    NULLIF(TRIM(gift_message), '') AS gift_message,
    NULLIF(TRIM(gift_sender), '') AS gift_sender,
    NULLIF(TRIM(message_from_buyer), '') AS message_from_buyer,
    NULLIF(TRIM(message_from_payment), '') AS message_from_payment,
    NULLIF(TRIM(message_from_seller), '') AS message_from_seller,

    -- money fields
    discount_amt,
    NULLIF(TRIM(discount_amt_currency), '') AS discount_amt_currency,
    subtotal,
    NULLIF(TRIM(subtotal_currency), '') AS subtotal_currency,
    grandtotal,
    NULLIF(TRIM(grandtotal_currency), '') AS grandtotal_currency,
    total_price,
    NULLIF(TRIM(total_price_currency), '') AS total_price_currency,
    total_shipping_cost,
    NULLIF(TRIM(total_shipping_cost_currency), '') AS total_shipping_cost_currency,
    total_tax_cost,
    NULLIF(TRIM(total_tax_cost_currency), '') AS total_tax_cost_currency,
    total_vat_cost,
    NULLIF(TRIM(total_vat_cost_currency), '') AS total_vat_cost_currency,
    gift_wrap_price,
    NULLIF(TRIM(gift_wrap_price_currency), '') AS gift_wrap_price_currency,

    -- json payloads retained for future modeling
    refunds_json,
    shipments_json,
    transactions_json,
    raw_json

FROM deduped;