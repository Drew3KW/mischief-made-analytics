-- Model: marts.fct_orders
-- Grain: one row per order
-- Purpose: order-level fact table for AOV, refund, and customer order analysis
--
-- Notes:
-- - Built from staging.stg_shopify_orders
-- - Serves as the main fact for order-level KPIs
-- - Adds flags for historical order-timestamp anomalies discovered during
--   Analysis Pack v1 monthly trend validation

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.fct_orders` AS

SELECT
  order_number,
  shopify_order_id,
  LOWER(TRIM(customer_email)) AS customer_email,
  created_at_ts,
  paid_at_ts,
  fulfilled_at_ts,
  cancelled_at_ts,
  financial_status,
  fulfillment_status,
  currency,
  order_source,
  risk_level,
  order_subtotal,
  order_shipping,
  order_taxes,
  order_total,
  order_discount_amount,
  refunded_amount,
  total_items,
  line_item_count,
  distinct_sku_count,
  billing_city,
  billing_province,
  billing_country,
  shipping_city,
  shipping_province,
  shipping_country,
  payment_method,
  shipping_method,
  tags,

  CASE
    WHEN DATE(created_at_ts) IN ('2021-01-22', '2021-01-23') THEN TRUE
    WHEN DATE(created_at_ts) < '2021-01-31' THEN TRUE
    WHEN REGEXP_CONTAINS(order_number, r'^[0-9]{6,}$') THEN TRUE
    ELSE FALSE
  END AS is_suspect_historical_timing,

  CASE
    WHEN REGEXP_CONTAINS(order_number, r'^#[0-9]+$') THEN 'modern_hash_order_number'
    WHEN REGEXP_CONTAINS(order_number, r'^[0-9]{6,}$') THEN 'legacy_numeric_order_number'
    ELSE 'other_order_number_format'
  END AS order_number_format

FROM `mischief-made-analytics.staging.stg_shopify_orders`;
