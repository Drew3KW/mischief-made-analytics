-- sql/staging/stg_etsy_receipt_payments.sql
-- Model: staging.stg_etsy_receipt_payments
-- Grain: one row per Etsy receipt payment
-- Purpose: cleaned and typed Etsy payment staging model
-- Notes:
-- - Etsy payment_id is the native Etsy payment key.
-- - Some receipts have no payment row because Etsy returned 404 for the receipt payment endpoint.
-- - adjusted_* fields may be null and are preserved as source-provided payment fields.

CREATE OR REPLACE TABLE `mischief-made-analytics.staging.stg_etsy_receipt_payments` AS

WITH source AS (
    SELECT *
    FROM `mischief-made-analytics.raw_load.etsy_receipt_payments_api_latest`
),

deduped AS (
    SELECT * EXCEPT(row_number)
    FROM (
        SELECT
            source.*,
            ROW_NUMBER() OVER (
                PARTITION BY payment_id
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
    payment_id,
    CAST(payment_id AS STRING) AS etsy_payment_key,
    receipt_id,
    CAST(receipt_id AS STRING) AS etsy_receipt_key,
    shop_id,

    -- customer and address identifiers
    buyer_user_id,
    CAST(buyer_user_id AS STRING) AS etsy_buyer_key,
    billing_address_id,
    shipping_address_id,
    shipping_user_id,

    -- status and currency
    NULLIF(TRIM(status), '') AS payment_status,
    NULLIF(TRIM(currency), '') AS currency,
    NULLIF(TRIM(buyer_currency), '') AS buyer_currency,
    NULLIF(TRIM(shop_currency), '') AS shop_currency,

    -- timestamps
    create_timestamp,
    created_timestamp,
    update_timestamp,
    updated_timestamp,
    shipped_timestamp,
    TIMESTAMP_SECONDS(COALESCE(created_timestamp, create_timestamp)) AS payment_created_at,
    DATE(TIMESTAMP_SECONDS(COALESCE(created_timestamp, create_timestamp))) AS payment_created_date,
    TIMESTAMP_SECONDS(COALESCE(updated_timestamp, update_timestamp)) AS payment_updated_at,
    DATE(TIMESTAMP_SECONDS(COALESCE(updated_timestamp, update_timestamp))) AS payment_updated_date,
    TIMESTAMP_SECONDS(shipped_timestamp) AS shipped_at,
    DATE(TIMESTAMP_SECONDS(shipped_timestamp)) AS shipped_date,

    -- original payment amounts
    amount_gross,
    NULLIF(TRIM(amount_gross_currency), '') AS amount_gross_currency,
    amount_fees,
    NULLIF(TRIM(amount_fees_currency), '') AS amount_fees_currency,
    amount_net,
    NULLIF(TRIM(amount_net_currency), '') AS amount_net_currency,

    -- adjusted payment amounts
    adjusted_gross,
    NULLIF(TRIM(adjusted_gross_currency), '') AS adjusted_gross_currency,
    adjusted_fees,
    NULLIF(TRIM(adjusted_fees_currency), '') AS adjusted_fees_currency,
    adjusted_net,
    NULLIF(TRIM(adjusted_net_currency), '') AS adjusted_net_currency,

    -- posted payment amounts
    posted_gross,
    NULLIF(TRIM(posted_gross_currency), '') AS posted_gross_currency,
    posted_fees,
    NULLIF(TRIM(posted_fees_currency), '') AS posted_fees_currency,
    posted_net,
    NULLIF(TRIM(posted_net_currency), '') AS posted_net_currency,

    -- practical payment fields for downstream marts
    COALESCE(adjusted_gross, amount_gross, posted_gross) AS selected_gross_amount,
    COALESCE(adjusted_fees, amount_fees, posted_fees) AS selected_fee_amount,
    COALESCE(adjusted_net, amount_net, posted_net) AS selected_net_amount,

    -- json payloads retained for future modeling
    payment_adjustments_json,
    raw_json

FROM deduped;