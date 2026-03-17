-- Model: staging.stg_shopify_order_items
-- Grain: one row per order line item
-- Purpose: cleaned and typed Shopify order item staging model
-- Notes:
--   - Source Shopify export is line-item grain
--   - Raw source was loaded as STRING for ingestion stability
--   - Order-level fields may repeat inconsistently across line items

CREATE OR REPLACE TABLE `mischief-made-analytics.staging.stg_shopify_order_items` AS

SELECT
  -- identifiers
  SAFE_CAST(`Id` AS INT64) AS shopify_order_id,
  `Name` AS order_number,
  `Lineitem sku` AS sku,
  `Lineitem name` AS product_name,

  -- customer
  LOWER(TRIM(`Email`)) AS customer_email,

  -- timestamps
  SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S %z', `Created at`) AS created_at_ts,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S %z', `Paid at`) AS paid_at_ts,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S %z', `Fulfilled at`) AS fulfilled_at_ts,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S %z', `Cancelled at`) AS cancelled_at_ts,

  -- status
  `Financial Status` AS financial_status,
  `Fulfillment Status` AS fulfillment_status,
  `Lineitem fulfillment status` AS lineitem_fulfillment_status,
  `Currency` AS currency,
  `Source` AS order_source,
  `Risk Level` AS risk_level,

  -- quantities
  SAFE_CAST(`Lineitem quantity` AS INT64) AS quantity,

  -- pricing
  SAFE_CAST(`Lineitem price` AS NUMERIC) AS lineitem_price,
  SAFE_CAST(`Lineitem compare at price` AS NUMERIC) AS compare_at_price,
  SAFE_CAST(`Lineitem discount` AS NUMERIC) AS lineitem_discount,

  -- order totals (repeated per line item)
  SAFE_CAST(`Subtotal` AS NUMERIC) AS order_subtotal,
  SAFE_CAST(`Shipping` AS NUMERIC) AS order_shipping,
  SAFE_CAST(`Taxes` AS NUMERIC) AS order_taxes,
  SAFE_CAST(`Total` AS NUMERIC) AS order_total,
  SAFE_CAST(`Discount Amount` AS NUMERIC) AS order_discount_amount,
  SAFE_CAST(`Refunded Amount` AS NUMERIC) AS refunded_amount,

  -- product metadata
  `Vendor` AS vendor,

  -- geography
  `Billing City` AS billing_city,
  `Billing Province` AS billing_province,
  `Billing Country` AS billing_country,
  `Shipping City` AS shipping_city,
  `Shipping Province` AS shipping_province,
  `Shipping Country` AS shipping_country,

  -- operations metadata
  `Payment Method` AS payment_method,
  `Shipping Method` AS shipping_method,
  `Tags` AS tags
  

FROM `mischief-made-analytics.raw.shopify_orders`;
