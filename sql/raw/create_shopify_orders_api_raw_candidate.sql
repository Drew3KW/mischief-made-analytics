-- File: sql/raw/create_shopify_orders_api_raw_candidate.sql
-- Model: raw_load.shopify_orders_api_raw_candidate
-- Purpose:
-- Create a CSV-compatible shadow raw orders candidate from isolated Shopify API
-- order and line item landing tables.
--
-- Important notes:
-- - This does not modify raw.shopify_orders.
-- - This does not modify staging, marts, or business-facing analysis.
-- - Output grain is one row per API order line item.
-- - Order-level fields repeat across line items to match the CSV-derived raw shape.
-- - Some CSV export fields are not available in the current API landing data
--   and are intentionally populated as NULL.

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.shopify_orders_api_raw_candidate` AS

WITH orders AS (
  SELECT
    shopify_order_graphql_id,
    legacy_resource_id,
    order_number,
    email,
    customer_email,
    created_at,
    processed_at,
    cancelled_at,
    display_financial_status,
    display_fulfillment_status,
    currency_code,
    presentment_currency_code,
    order_source,
    tags_json,
    current_subtotal_price,
    current_shipping_price,
    current_total_tax,
    current_total_price,
    current_total_discounts,
    total_refunded,
    money_currency_code,
    billing_city,
    billing_province_code,
    billing_country_code,
    shipping_city,
    shipping_province_code,
    shipping_country_code,
    payment_gateway_names_json,
    shipping_line_title
  FROM `mischief-made-analytics.raw_load.shopify_orders_api_latest`
),

line_items AS (
  SELECT
    shopify_line_item_graphql_id,
    shopify_order_graphql_id,
    line_item_name,
    title,
    variant_title,
    sku,
    vendor,
    quantity,
    current_quantity,
    original_unit_price,
    discounted_unit_price,
    discounted_total,
    total_discount
  FROM `mischief-made-analytics.raw_load.shopify_order_line_items_api_latest`
)

SELECT
  orders.legacy_resource_id AS `Id`,
  orders.order_number AS `Name`,
  line_items.sku AS `Lineitem sku`,
  COALESCE(line_items.line_item_name, line_items.title) AS `Lineitem name`,

  COALESCE(NULLIF(TRIM(orders.email), ''), NULLIF(TRIM(orders.customer_email), '')) AS `Email`,

  FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S %z', orders.created_at) AS `Created at`,
  FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S %z', orders.processed_at) AS `Paid at`,
  CAST(NULL AS STRING) AS `Fulfilled at`,
  FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S %z', orders.cancelled_at) AS `Cancelled at`,

  LOWER(REPLACE(orders.display_financial_status, '_', ' ')) AS `Financial Status`,
  LOWER(REPLACE(orders.display_fulfillment_status, '_', ' ')) AS `Fulfillment Status`,
  LOWER(REPLACE(orders.display_fulfillment_status, '_', ' ')) AS `Lineitem fulfillment status`,

  COALESCE(
    orders.currency_code,
    orders.presentment_currency_code,
    orders.money_currency_code
  ) AS `Currency`,

  orders.order_source AS `Source`,
  CAST(NULL AS STRING) AS `Risk Level`,

  CAST(line_items.quantity AS STRING) AS `Lineitem quantity`,
  line_items.original_unit_price AS `Lineitem price`,
  CAST(NULL AS STRING) AS `Lineitem compare at price`,
  line_items.total_discount AS `Lineitem discount`,

  orders.current_subtotal_price AS `Subtotal`,
  orders.current_shipping_price AS `Shipping`,
  orders.current_total_tax AS `Taxes`,
  orders.current_total_price AS `Total`,
  orders.current_total_discounts AS `Discount Amount`,
  orders.total_refunded AS `Refunded Amount`,

  line_items.vendor AS `Vendor`,

  orders.billing_city AS `Billing City`,
  orders.billing_province_code AS `Billing Province`,
  orders.billing_country_code AS `Billing Country`,
  orders.shipping_city AS `Shipping City`,
  orders.shipping_province_code AS `Shipping Province`,
  orders.shipping_country_code AS `Shipping Country`,

  COALESCE(
    ARRAY_TO_STRING(JSON_VALUE_ARRAY(orders.payment_gateway_names_json, '$'), ', '),
    ''
  ) AS `Payment Method`,

  orders.shipping_line_title AS `Shipping Method`,

  COALESCE(
    ARRAY_TO_STRING(JSON_VALUE_ARRAY(orders.tags_json, '$'), ', '),
    ''
  ) AS `Tags`

FROM line_items
LEFT JOIN orders
  ON line_items.shopify_order_graphql_id = orders.shopify_order_graphql_id;