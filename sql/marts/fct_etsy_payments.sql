-- sql/marts/fct_etsy_payments.sql
-- Model: marts.fct_etsy_payments
-- Grain: one row per Etsy receipt payment
-- Purpose:
-- Etsy-native payment fact built from staged Etsy receipt payments.
--
-- Notes:
-- - payment_id is the Etsy-native payment key.
-- - selected_* fields coalesce adjusted, original, and posted Etsy payment amounts.
-- - Etsy payment net is channel-reported payment net, not full accounting net.

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.fct_etsy_payments` AS

WITH payments AS (
    SELECT *
    FROM `mischief-made-analytics.staging.stg_etsy_receipt_payments`
),

receipts AS (
    SELECT
        receipt_id,
        etsy_receipt_key,
        receipt_status,
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
    CONCAT('etsy:', CAST(p.payment_id AS STRING)) AS cross_channel_payment_key,
    CONCAT('etsy:', CAST(p.receipt_id AS STRING)) AS cross_channel_order_key,
    p.etsy_payment_key,
    p.etsy_receipt_key AS etsy_order_key,
    p.payment_id,
    p.receipt_id,

    -- order context
    r.receipt_status,
    r.receipt_created_at AS order_created_at,
    r.receipt_created_date AS order_date,

    -- customer and shop
    COALESCE(p.buyer_user_id, r.buyer_user_id) AS buyer_user_id,
    COALESCE(p.etsy_buyer_key, r.etsy_buyer_key) AS etsy_buyer_key,
    r.buyer_email,
    p.shop_id,

    -- payment status and currency
    p.payment_status,
    p.currency,
    p.buyer_currency,
    p.shop_currency,

    -- payment dates
    p.payment_created_at,
    p.payment_created_date,
    p.payment_updated_at,
    p.payment_updated_date,
    p.shipped_at,
    p.shipped_date,

    -- original payment amounts
    COALESCE(p.amount_gross, 0) AS amount_gross,
    p.amount_gross_currency,
    COALESCE(p.amount_fees, 0) AS amount_fees,
    p.amount_fees_currency,
    COALESCE(p.amount_net, 0) AS amount_net,
    p.amount_net_currency,

    -- adjusted payment amounts
    COALESCE(p.adjusted_gross, 0) AS adjusted_gross,
    p.adjusted_gross_currency,
    COALESCE(p.adjusted_fees, 0) AS adjusted_fees,
    p.adjusted_fees_currency,
    COALESCE(p.adjusted_net, 0) AS adjusted_net,
    p.adjusted_net_currency,

    -- posted payment amounts
    COALESCE(p.posted_gross, 0) AS posted_gross,
    p.posted_gross_currency,
    COALESCE(p.posted_fees, 0) AS posted_fees,
    p.posted_fees_currency,
    COALESCE(p.posted_net, 0) AS posted_net,
    p.posted_net_currency,

    -- selected practical payment amounts
    COALESCE(p.selected_gross_amount, 0) AS selected_gross_amount,
    COALESCE(p.selected_fee_amount, 0) AS selected_fee_amount,
    COALESCE(p.selected_net_amount, 0) AS selected_net_amount,

    -- practical flags
    r.receipt_id IS NULL AS missing_receipt_record,
    p.adjusted_net IS NOT NULL AS used_adjusted_net,

    -- source metadata
    p.landing_run_id,
    p.landing_loaded_at

FROM payments AS p
LEFT JOIN receipts AS r
    ON p.receipt_id = r.receipt_id;