-- File: sql/raw/create_shopify_customers_api_raw_candidate.sql
-- Model: raw_load.shopify_customers_api_raw_candidate
-- Purpose:
-- Create a CSV-compatible shadow raw customers candidate from the isolated
-- Shopify API customer landing table.
--
-- Important notes:
-- - This does not modify raw.shopify_customers.
-- - This does not modify staging, marts, or business-facing analysis.
-- - This table is for contract testing before any future canonical raw rebuild.

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.shopify_customers_api_raw_candidate` AS

SELECT
  legacy_resource_id AS customer_id,
  email,
  first_name,
  last_name,

  CASE
    WHEN email_marketing_state = 'SUBSCRIBED' THEN 'yes'
    WHEN email_marketing_state IS NULL THEN NULL
    ELSE 'no'
  END AS accepts_email_marketing,

  CASE
    WHEN sms_marketing_state = 'SUBSCRIBED' THEN 'yes'
    WHEN sms_marketing_state IS NULL THEN NULL
    ELSE 'no'
  END AS accepts_sms_marketing,

  default_address_company,
  default_address_address1,
  default_address_address2,
  default_address_city,
  default_address_province_code,
  default_address_country_code,
  default_address_zip,
  default_address_phone,
  phone,

  amount_spent AS total_spent,
  CAST(number_of_orders AS STRING) AS total_orders,
  note,

  CASE
    WHEN tax_exempt IS TRUE THEN 'yes'
    WHEN tax_exempt IS FALSE THEN 'no'
    ELSE NULL
  END AS tax_exempt,

  COALESCE(ARRAY_TO_STRING(JSON_VALUE_ARRAY(tags_json, '$'), ', '), '') AS tags

FROM `mischief-made-analytics.raw_load.shopify_customers_api_latest`;