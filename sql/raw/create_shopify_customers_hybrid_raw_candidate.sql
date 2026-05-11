-- File: sql/raw/create_shopify_customers_hybrid_raw_candidate.sql
-- Model: raw_load.shopify_customers_hybrid_raw_candidate
-- Purpose:
-- Create a non-production hybrid raw customers candidate by combining:
-- 1) current CSV-derived canonical raw customers
-- 2) API-derived raw customer candidates
--
-- Important notes:
-- - This does not modify raw.shopify_customers.
-- - This does not modify staging, marts, analysis, or DAG behavior.
-- - API-derived rows win when they share the same dedupe key as CSV-derived rows.
-- - This table is for validation before any future canonical raw replacement.

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.shopify_customers_hybrid_raw_candidate` AS

WITH combined AS (
  SELECT
    CAST(customer_id AS STRING) AS customer_id,
    CAST(email AS STRING) AS email,
    CAST(first_name AS STRING) AS first_name,
    CAST(last_name AS STRING) AS last_name,
    CAST(accepts_email_marketing AS STRING) AS accepts_email_marketing,
    CAST(accepts_sms_marketing AS STRING) AS accepts_sms_marketing,
    CAST(default_address_company AS STRING) AS default_address_company,
    CAST(default_address_address1 AS STRING) AS default_address_address1,
    CAST(default_address_address2 AS STRING) AS default_address_address2,
    CAST(default_address_city AS STRING) AS default_address_city,
    CAST(default_address_province_code AS STRING) AS default_address_province_code,
    CAST(default_address_country_code AS STRING) AS default_address_country_code,
    CAST(default_address_zip AS STRING) AS default_address_zip,
    CAST(default_address_phone AS STRING) AS default_address_phone,
    CAST(phone AS STRING) AS phone,
    CAST(total_spent AS STRING) AS total_spent,
    CAST(total_orders AS STRING) AS total_orders,
    CAST(note AS STRING) AS note,
    CAST(tax_exempt AS STRING) AS tax_exempt,
    CAST(tags AS STRING) AS tags,
    'csv_current_raw' AS _hybrid_source,
    0 AS source_rank
  FROM `mischief-made-analytics.raw.shopify_customers`

  UNION ALL

  SELECT
    CAST(customer_id AS STRING) AS customer_id,
    CAST(email AS STRING) AS email,
    CAST(first_name AS STRING) AS first_name,
    CAST(last_name AS STRING) AS last_name,
    CAST(accepts_email_marketing AS STRING) AS accepts_email_marketing,
    CAST(accepts_sms_marketing AS STRING) AS accepts_sms_marketing,
    CAST(default_address_company AS STRING) AS default_address_company,
    CAST(default_address_address1 AS STRING) AS default_address_address1,
    CAST(default_address_address2 AS STRING) AS default_address_address2,
    CAST(default_address_city AS STRING) AS default_address_city,
    CAST(default_address_province_code AS STRING) AS default_address_province_code,
    CAST(default_address_country_code AS STRING) AS default_address_country_code,
    CAST(default_address_zip AS STRING) AS default_address_zip,
    CAST(default_address_phone AS STRING) AS default_address_phone,
    CAST(phone AS STRING) AS phone,
    CAST(total_spent AS STRING) AS total_spent,
    CAST(total_orders AS STRING) AS total_orders,
    CAST(note AS STRING) AS note,
    CAST(tax_exempt AS STRING) AS tax_exempt,
    CAST(tags AS STRING) AS tags,
    'api_raw_candidate' AS _hybrid_source,
    1 AS source_rank
  FROM `mischief-made-analytics.raw_load.shopify_customers_api_raw_candidate`
),

keyed AS (
  SELECT
    *,
    CASE
      WHEN NULLIF(TRIM(customer_id), '') IS NOT NULL THEN
        CONCAT('customer_id::', TRIM(customer_id))
      WHEN NULLIF(LOWER(TRIM(email)), '') IS NOT NULL THEN
        CONCAT('email::', LOWER(TRIM(email)))
      ELSE
        CONCAT(
          'fingerprint::',
          TO_HEX(
            MD5(
              TO_JSON_STRING(
                STRUCT(
                  customer_id,
                  email,
                  first_name,
                  last_name,
                  phone,
                  default_address_address1,
                  default_address_zip
                )
              )
            )
          )
        )
    END AS dedupe_key
  FROM combined
),

deduped AS (
  SELECT * EXCEPT(source_rank, dedupe_key)
  FROM keyed
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY dedupe_key
    ORDER BY source_rank DESC
  ) = 1
)

SELECT *
FROM deduped;