-- Model: marts.dim_customers
-- Grain: one row per nonblank customer_email
-- Purpose: customer dimension combining customer export attributes with order-history rollups
-- Notes:
--   - customer_email is the current practical customer key
--   - Some fact rows may remain unmatched due to guest checkout or export differences

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.dim_customers` AS

WITH customer_base AS (
  SELECT
    LOWER(TRIM(customer_email)) AS customer_email,
    shopify_customer_id,
    first_name,
    last_name,
    accepts_email_marketing,
    accepts_sms_marketing,
    total_orders,
    total_spent,
    tax_exempt,
    default_address_city,
    default_address_province_code,
    default_address_country_code,
    default_address_zip
  FROM `mischief-made-analytics.staging.stg_shopify_customers`
  WHERE customer_email IS NOT NULL
    AND TRIM(customer_email) <> ''
),

order_rollup AS (
  SELECT
    LOWER(TRIM(customer_email)) AS customer_email,
    MIN(created_at_ts) AS first_order_at,
    MAX(created_at_ts) AS last_order_at,
    COUNT(DISTINCT order_number) AS lifetime_order_count_from_orders
  FROM `mischief-made-analytics.staging.stg_shopify_orders`
  WHERE customer_email IS NOT NULL
    AND TRIM(customer_email) <> ''
  GROUP BY 1
)

SELECT
  c.customer_email,
  c.shopify_customer_id,
  c.first_name,
  c.last_name,
  c.accepts_email_marketing,
  c.accepts_sms_marketing,
  c.total_orders,
  c.total_spent,
  c.tax_exempt,
  c.default_address_city,
  c.default_address_province_code,
  c.default_address_country_code,
  c.default_address_zip,
  o.first_order_at,
  o.last_order_at,
  o.lifetime_order_count_from_orders
FROM customer_base c
LEFT JOIN order_rollup o
  ON c.customer_email = o.customer_email;
