-- File: sql/staging/create_stg_shopify_customers_api_shadow.sql
-- Model: raw_load.stg_shopify_customers_api_shadow
-- Purpose:
-- Apply the current customers staging contract to the Shopify API raw candidate.
--
-- Important notes:
-- - This does not modify staging.stg_shopify_customers.
-- - This does not modify marts or business-facing analysis.
-- - This table is for shadow comparison only.

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.stg_shopify_customers_api_shadow` AS

SELECT
  SAFE_CAST(customer_id AS INT64) AS shopify_customer_id,
  LOWER(TRIM(email)) AS customer_email,
  TRIM(first_name) AS first_name,
  TRIM(last_name) AS last_name,
  accepts_email_marketing,
  accepts_sms_marketing,
  TRIM(default_address_company) AS default_address_company,
  TRIM(default_address_address1) AS default_address_address1,
  TRIM(default_address_address2) AS default_address_address2,
  TRIM(default_address_city) AS default_address_city,
  TRIM(default_address_province_code) AS default_address_province_code,
  TRIM(default_address_country_code) AS default_address_country_code,
  TRIM(default_address_zip) AS default_address_zip,
  TRIM(default_address_phone) AS default_address_phone,
  TRIM(phone) AS phone,
  SAFE_CAST(total_spent AS NUMERIC) AS total_spent,
  SAFE_CAST(total_orders AS INT64) AS total_orders,
  TRIM(note) AS note,
  tax_exempt,
  tags

FROM `mischief-made-analytics.raw_load.shopify_customers_api_raw_candidate`;