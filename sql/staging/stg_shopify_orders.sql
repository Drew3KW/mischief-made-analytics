-- Model: staging.stg_shopify_orders
-- Grain: one row per order
-- Purpose: cleaned and typed Shopify order staging model
-- Notes:
--   - order_number is the practical business-facing order key
--   - Built from line-item-grain Shopify export with order-level rollup logic

CREATE OR REPLACE TABLE `mischief-made-analytics.staging.stg_shopify_orders` AS

SELECT
  -- keys
  MAX(shopify_order_id) AS shopify_order_id,
  order_number,

  -- customer
  MAX(customer_email) AS customer_email,

  -- timestamps
  MAX(created_at_ts) AS created_at_ts,
  MAX(paid_at_ts) AS paid_at_ts,
  MAX(fulfilled_at_ts) AS fulfilled_at_ts,
  MAX(cancelled_at_ts) AS cancelled_at_ts,

  -- statuses
  MAX(financial_status) AS financial_status,
  MAX(fulfillment_status) AS fulfillment_status,
  MAX(currency) AS currency,
  MAX(order_source) AS order_source,
  MAX(risk_level) AS risk_level,

  -- order-level money
  MAX(order_subtotal) AS order_subtotal,
  MAX(order_shipping) AS order_shipping,
  MAX(order_taxes) AS order_taxes,
  MAX(order_total) AS order_total,
  MAX(order_discount_amount) AS order_discount_amount,
  MAX(refunded_amount) AS refunded_amount,

  -- rolled-up line item metrics
  SUM(quantity) AS total_items,
  COUNT(*) AS line_item_count,
  COUNT(DISTINCT sku) AS distinct_sku_count,

  -- geography
  MAX(billing_city) AS billing_city,
  MAX(billing_province) AS billing_province,
  MAX(billing_country) AS billing_country,
  MAX(shipping_city) AS shipping_city,
  MAX(shipping_province) AS shipping_province,
  MAX(shipping_country) AS shipping_country,

  -- operational metadata
  MAX(payment_method) AS payment_method,
  MAX(shipping_method) AS shipping_method,
  MAX(tags) AS tags

FROM `mischief-made-analytics.staging.stg_shopify_order_items`
GROUP BY
  order_number;
