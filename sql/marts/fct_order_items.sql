-- Model: marts.fct_order_items
-- Grain: one row per order line item
-- Purpose: line-item fact table for product and item-level sales analysis
-- Notes:
--   - Uses product_key to join to dim_products_historical
--   - Repeated order-level monetary fields were removed from this fact
--   - order_item_key is synthetically generated for uniqueness

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.fct_order_items` AS

WITH base AS (
  SELECT
    shopify_order_id,
    order_number,
    sku,
    product_name,
    LOWER(TRIM(customer_email)) AS customer_email,

    created_at_ts,
    paid_at_ts,
    fulfilled_at_ts,
    cancelled_at_ts,

    financial_status,
    fulfillment_status,
    lineitem_fulfillment_status,
    currency,
    order_source,
    risk_level,

    quantity,
    lineitem_price,
    compare_at_price,
    lineitem_discount,

    vendor,

    billing_city,
    billing_province,
    billing_country,
    shipping_city,
    shipping_province,
    shipping_country,

    payment_method,
    shipping_method,
    tags,

    ROW_NUMBER() OVER (
      PARTITION BY order_number
      ORDER BY
        COALESCE(sku, ''),
        COALESCE(product_name, ''),
        COALESCE(quantity, 0),
        COALESCE(lineitem_price, 0)
    ) AS order_item_number
  FROM `mischief-made-analytics.staging.stg_shopify_order_items`
)

SELECT
  CONCAT(order_number, '-', LPAD(CAST(order_item_number AS STRING), 3, '0')) AS order_item_key,

  shopify_order_id,
  order_number,
  order_item_number,

  sku,
  product_name,
  customer_email,

  created_at_ts,
  paid_at_ts,
  fulfilled_at_ts,
  cancelled_at_ts,

  financial_status,
  fulfillment_status,
  lineitem_fulfillment_status,
  currency,
  order_source,
  risk_level,

  quantity,
  lineitem_price,
  compare_at_price,
  lineitem_discount,

  quantity * lineitem_price AS gross_item_revenue,
  (quantity * lineitem_price) - COALESCE(lineitem_discount, 0) AS net_item_revenue_before_refunds,

  vendor,

  billing_city,
  billing_province,
  billing_country,
  shipping_city,
  shipping_province,
  shipping_country,

  payment_method,
  shipping_method,
  tags
FROM base;
