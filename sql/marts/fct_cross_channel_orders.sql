-- Model: marts.fct_cross_channel_orders
-- Grain: one row per channel order
-- Purpose: first cross-channel order-level revenue fact for Shopify and Etsy
--
-- Notes:
-- - Shopify rows come from marts.fct_orders.
-- - Etsy rows come from raw_load Etsy landing tables created in Milestone 45.
-- - This model is channel-aware and does not merge Shopify and Etsy customers.
-- - This model does not perform product-family harmonization.
-- - Etsy payment records are optional because some receipt payment endpoint calls returned 404.
-- - Ledger entries are excluded because they are payout/accounting records, not order revenue rows.

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.fct_cross_channel_orders` AS

WITH shopify_orders AS (
    SELECT
        'shopify' AS channel,
        CAST(order_number AS STRING) AS channel_order_id,
        CONCAT('shopify:', CAST(order_number AS STRING)) AS cross_channel_order_key,
        CAST(shopify_order_id AS STRING) AS source_order_id,
        LOWER(TRIM(customer_email)) AS channel_customer_key,
        'email' AS channel_customer_key_type,

        created_at_ts AS order_created_at,
        paid_at_ts AS order_paid_at,
        DATE(created_at_ts) AS order_date,

        financial_status,
        fulfillment_status,

        CASE
            WHEN cancelled_at_ts IS NOT NULL THEN TRUE
            WHEN LOWER(COALESCE(financial_status, '')) IN ('voided', 'cancelled') THEN TRUE
            ELSE FALSE
        END AS is_cancelled,

        CASE
            WHEN COALESCE(refunded_amount, 0) > 0 THEN TRUE
            ELSE FALSE
        END AS has_refund,

        is_suspect_historical_timing,

        currency,

        CAST(order_subtotal AS NUMERIC) AS subtotal_amount,
        CAST(order_discount_amount AS NUMERIC) AS discount_amount,
        CAST(order_shipping AS NUMERIC) AS shipping_amount,
        CAST(order_taxes AS NUMERIC) AS tax_amount,
        CAST(order_total AS NUMERIC) AS gross_amount,
        CAST(refunded_amount AS NUMERIC) AS refund_amount,
        CAST(NULL AS NUMERIC) AS fee_amount,

        CAST(order_total AS NUMERIC) AS payment_gross_amount,
        CAST(NULL AS NUMERIC) AS payment_fee_amount,
        CAST(NULL AS NUMERIC) AS payment_net_amount,

        CAST(order_total - COALESCE(refunded_amount, 0) AS NUMERIC) AS net_revenue_after_refunds,
        CAST(order_total - COALESCE(refunded_amount, 0) AS NUMERIC) AS channel_reported_net_amount,

        total_items,
        line_item_count,
        distinct_sku_count,

        'marts.fct_orders' AS source_table,
        CAST(NULL AS STRING) AS landing_run_id,
        CAST(NULL AS TIMESTAMP) AS landing_loaded_at,

        CAST(NULL AS STRING) AS source_edge_case_notes

    FROM `mischief-made-analytics.marts.fct_orders`
    WHERE created_at_ts IS NOT NULL
      AND is_suspect_historical_timing = FALSE
),

etsy_payment_rollup AS (
    SELECT
        receipt_id,

        COUNT(*) AS payment_record_count,

        SUM(COALESCE(amount_gross, 0)) AS amount_gross,
        SUM(COALESCE(amount_fees, 0)) AS amount_fees,
        SUM(COALESCE(amount_net, 0)) AS amount_net,

        SUM(COALESCE(adjusted_gross, 0)) AS adjusted_gross,
        SUM(COALESCE(adjusted_fees, 0)) AS adjusted_fees,
        SUM(COALESCE(adjusted_net, 0)) AS adjusted_net,

        SUM(COALESCE(posted_gross, 0)) AS posted_gross,
        SUM(COALESCE(posted_fees, 0)) AS posted_fees,
        SUM(COALESCE(posted_net, 0)) AS posted_net,

        ARRAY_AGG(DISTINCT currency IGNORE NULLS LIMIT 1)[SAFE_OFFSET(0)] AS currency,
        ARRAY_AGG(DISTINCT landing_run_id IGNORE NULLS LIMIT 1)[SAFE_OFFSET(0)] AS landing_run_id,
        MAX(landing_loaded_at) AS landing_loaded_at

    FROM `mischief-made-analytics.raw_load.etsy_receipt_payments_api_latest`
    GROUP BY receipt_id
),

etsy_transaction_rollup AS (
    SELECT
        receipt_id,
        SUM(COALESCE(quantity, 0)) AS total_items,
        COUNT(DISTINCT transaction_id) AS line_item_count,
        COUNT(DISTINCT NULLIF(TRIM(sku), '')) AS distinct_sku_count,
        SUM(COALESCE(price, 0) * COALESCE(quantity, 0)) AS gross_item_amount,
        SUM(COALESCE(shipping_cost, 0)) AS transaction_shipping_amount
    FROM `mischief-made-analytics.raw_load.etsy_receipt_transactions_api_latest`
    GROUP BY receipt_id
),

etsy_refund_rollup AS (
    SELECT
        receipt_id,
        SUM(
            SAFE_CAST(JSON_VALUE(refund_json, '$.amount.amount') AS NUMERIC)
            / NULLIF(SAFE_CAST(JSON_VALUE(refund_json, '$.amount.divisor') AS NUMERIC), 0)
        ) AS refund_amount
    FROM `mischief-made-analytics.raw_load.etsy_receipts_api_latest`,
    UNNEST(JSON_EXTRACT_ARRAY(refunds_json)) AS refund_json
    GROUP BY receipt_id
),

etsy_orders AS (
    SELECT
        'etsy' AS channel,
        CAST(r.receipt_id AS STRING) AS channel_order_id,
        CONCAT('etsy:', CAST(r.receipt_id AS STRING)) AS cross_channel_order_key,
        CAST(r.receipt_id AS STRING) AS source_order_id,

        CASE
            WHEN r.buyer_email IS NOT NULL AND TRIM(r.buyer_email) <> ''
                THEN LOWER(TRIM(r.buyer_email))
            WHEN r.buyer_user_id IS NOT NULL
                THEN CAST(r.buyer_user_id AS STRING)
            ELSE NULL
        END AS channel_customer_key,

        CASE
            WHEN r.buyer_email IS NOT NULL AND TRIM(r.buyer_email) <> '' THEN 'email'
            WHEN r.buyer_user_id IS NOT NULL THEN 'etsy_buyer_user_id'
            ELSE NULL
        END AS channel_customer_key_type,

        TIMESTAMP_SECONDS(COALESCE(r.created_timestamp, r.create_timestamp)) AS order_created_at,
        CAST(NULL AS TIMESTAMP) AS order_paid_at,
        DATE(TIMESTAMP_SECONDS(COALESCE(r.created_timestamp, r.create_timestamp))) AS order_date,

        r.status AS financial_status,
        CAST(NULL AS STRING) AS fulfillment_status,

        CASE
            WHEN LOWER(COALESCE(r.status, '')) IN ('canceled', 'cancelled') THEN TRUE
            ELSE FALSE
        END AS is_cancelled,

        CASE
            WHEN COALESCE(er.refund_amount, 0) > 0 THEN TRUE
            ELSE FALSE
        END AS has_refund,

        FALSE AS is_suspect_historical_timing,

        COALESCE(r.grandtotal_currency, r.total_price_currency, ep.currency) AS currency,

        CAST(r.subtotal AS NUMERIC) AS subtotal_amount,
        CAST(r.discount_amt AS NUMERIC) AS discount_amount,
        CAST(r.total_shipping_cost AS NUMERIC) AS shipping_amount,
        CAST(COALESCE(r.total_tax_cost, 0) + COALESCE(r.total_vat_cost, 0) AS NUMERIC) AS tax_amount,

        CAST(COALESCE(r.grandtotal, r.total_price) AS NUMERIC) AS gross_amount,
        CAST(COALESCE(er.refund_amount, 0) AS NUMERIC) AS refund_amount,
        CAST(ep.amount_fees AS NUMERIC) AS fee_amount,

        CAST(ep.amount_gross AS NUMERIC) AS payment_gross_amount,
        CAST(ep.amount_fees AS NUMERIC) AS payment_fee_amount,
        CAST(ep.amount_net AS NUMERIC) AS payment_net_amount,

        CAST(COALESCE(r.grandtotal, r.total_price) - COALESCE(er.refund_amount, 0) AS NUMERIC) AS net_revenue_after_refunds,

        CAST(
            CASE
                WHEN ep.adjusted_net IS NOT NULL AND ep.adjusted_net != 0 THEN ep.adjusted_net
                WHEN ep.amount_net IS NOT NULL AND ep.amount_net != 0 THEN ep.amount_net
                ELSE COALESCE(r.grandtotal, r.total_price) - COALESCE(er.refund_amount, 0)
            END AS NUMERIC
        ) AS channel_reported_net_amount,

        CAST(et.total_items AS INT64) AS total_items,
        CAST(et.line_item_count AS INT64) AS line_item_count,
        CAST(et.distinct_sku_count AS INT64) AS distinct_sku_count,

        'raw_load.etsy_receipts_api_latest' AS source_table,
        r.landing_run_id,
        r.landing_loaded_at,

        CASE
            WHEN ep.receipt_id IS NULL THEN 'missing_etsy_payment_record'
            WHEN et.receipt_id IS NULL THEN 'missing_etsy_transaction_record'
            ELSE NULL
        END AS source_edge_case_notes

    FROM `mischief-made-analytics.raw_load.etsy_receipts_api_latest` AS r
    LEFT JOIN etsy_payment_rollup AS ep
        ON r.receipt_id = ep.receipt_id
    LEFT JOIN etsy_transaction_rollup AS et
        ON r.receipt_id = et.receipt_id
    LEFT JOIN etsy_refund_rollup AS er
        ON r.receipt_id = er.receipt_id
    WHERE COALESCE(r.created_timestamp, r.create_timestamp) IS NOT NULL
)

SELECT *
FROM shopify_orders

UNION ALL

SELECT *
FROM etsy_orders;