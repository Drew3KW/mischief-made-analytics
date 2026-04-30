-- sql/analysis/shopify_api_csv_customer_reconciliation.sql
-- Purpose:
-- Reconcile Shopify API customer landing data against the existing
-- CSV-derived customer warehouse shape.
--
-- Grain:
-- One row per unified Shopify customer ID from either the API landing table
-- or the current CSV-derived staging customer table.
--
-- Notes:
-- - This is comparison-only.
-- - This does not modify canonical raw tables.
-- - This does not replace the CSV ingestion path.
-- - This does not change staging, marts, or business-facing analysis logic.

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_shopify_api_csv_customer_reconciliation` AS

WITH
  api_customers AS (
    SELECT
      shopify_customer_graphql_id,
      SAFE_CAST(legacy_resource_id AS INT64) AS api_shopify_customer_id,
      LOWER(TRIM(email)) AS api_normalized_email,
      email AS api_email,
      first_name AS api_first_name,
      last_name AS api_last_name,
      display_name AS api_display_name,
      phone AS api_phone,
      email_marketing_state AS api_email_marketing_state,
      email_marketing_opt_in_level AS api_email_marketing_opt_in_level,
      sms_marketing_state AS api_sms_marketing_state,
      sms_marketing_opt_in_level AS api_sms_marketing_opt_in_level,
      state AS api_customer_state,
      verified_email AS api_verified_email,
      tax_exempt AS api_tax_exempt,
      number_of_orders AS api_number_of_orders,
      SAFE_CAST(NULLIF(TRIM(amount_spent), '') AS NUMERIC) AS api_amount_spent,
      amount_spent_currency AS api_amount_spent_currency,
      created_at AS api_customer_created_at,
      updated_at AS api_customer_updated_at,
      note AS api_note,
      tags_json AS api_tags_json,
      default_address_company AS api_default_address_company,
      default_address_address1 AS api_default_address_address1,
      default_address_address2 AS api_default_address_address2,
      default_address_city AS api_default_address_city,
      default_address_province_code AS api_default_address_province_code,
      default_address_country_code AS api_default_address_country_code,
      default_address_zip AS api_default_address_zip,
      default_address_phone AS api_default_address_phone
    FROM `mischief-made-analytics.raw_load.shopify_customers_api_latest`
  ),

  raw_customers AS (
    SELECT
      SAFE_CAST(customer_id AS INT64) AS raw_shopify_customer_id,
      LOWER(TRIM(email)) AS raw_normalized_email,
      email AS raw_email,
      first_name AS raw_first_name,
      last_name AS raw_last_name,
      accepts_email_marketing AS raw_accepts_email_marketing,
      accepts_sms_marketing AS raw_accepts_sms_marketing,
      phone AS raw_phone,
      SAFE_CAST(NULLIF(TRIM(total_spent), '') AS NUMERIC) AS raw_total_spent,
      SAFE_CAST(NULLIF(TRIM(total_orders), '') AS INT64) AS raw_total_orders,
      note AS raw_note,
      tax_exempt AS raw_tax_exempt,
      tags AS raw_tags,
      default_address_company AS raw_default_address_company,
      default_address_address1 AS raw_default_address_address1,
      default_address_address2 AS raw_default_address_address2,
      default_address_city AS raw_default_address_city,
      default_address_province_code AS raw_default_address_province_code,
      default_address_country_code AS raw_default_address_country_code,
      default_address_zip AS raw_default_address_zip,
      default_address_phone AS raw_default_address_phone
    FROM `mischief-made-analytics.raw.shopify_customers`
  ),

  staging_customers AS (
    SELECT
      shopify_customer_id AS staging_shopify_customer_id,
      LOWER(TRIM(customer_email)) AS staging_normalized_email,
      customer_email AS staging_customer_email,
      first_name AS staging_first_name,
      last_name AS staging_last_name,
      accepts_email_marketing AS staging_accepts_email_marketing,
      accepts_sms_marketing AS staging_accepts_sms_marketing,
      phone AS staging_phone,
      total_spent AS staging_total_spent,
      total_orders AS staging_total_orders,
      note AS staging_note,
      tax_exempt AS staging_tax_exempt,
      CASE
        WHEN LOWER(TRIM(tax_exempt)) IN ('true', 'yes', 'y', '1') THEN TRUE
        WHEN LOWER(TRIM(tax_exempt)) IN ('false', 'no', 'n', '0') THEN FALSE
        ELSE NULL
      END AS staging_tax_exempt_bool,
      tags AS staging_tags,
      default_address_company AS staging_default_address_company,
      default_address_address1 AS staging_default_address_address1,
      default_address_address2 AS staging_default_address_address2,
      default_address_city AS staging_default_address_city,
      default_address_province_code AS staging_default_address_province_code,
      default_address_country_code AS staging_default_address_country_code,
      default_address_zip AS staging_default_address_zip,
      default_address_phone AS staging_default_address_phone
    FROM `mischief-made-analytics.staging.stg_shopify_customers`
  ),

  dim_customers AS (
    SELECT
      shopify_customer_id AS dim_shopify_customer_id,
      LOWER(TRIM(customer_email)) AS dim_normalized_email,
      customer_email AS dim_customer_email,
      first_name AS dim_first_name,
      last_name AS dim_last_name,
      accepts_email_marketing AS dim_accepts_email_marketing,
      accepts_sms_marketing AS dim_accepts_sms_marketing,
      total_orders AS dim_total_orders,
      total_spent AS dim_total_spent,
      tax_exempt AS dim_tax_exempt,
      default_address_city AS dim_default_address_city,
      default_address_province_code AS dim_default_address_province_code,
      default_address_country_code AS dim_default_address_country_code,
      default_address_zip AS dim_default_address_zip,
      first_order_at,
      last_order_at,
      lifetime_order_count_from_orders
    FROM `mischief-made-analytics.marts.dim_customers`
  ),

  api_staging_joined AS (
    SELECT
      COALESCE(
        api.api_shopify_customer_id,
        staging.staging_shopify_customer_id
      ) AS unified_shopify_customer_id,

      api.shopify_customer_graphql_id,
      api.api_shopify_customer_id,
      staging.staging_shopify_customer_id,

      api.api_normalized_email,
      api.api_email,
      staging.staging_normalized_email,
      staging.staging_customer_email,

      api.api_first_name,
      api.api_last_name,
      api.api_display_name,
      staging.staging_first_name,
      staging.staging_last_name,

      api.api_phone,
      staging.staging_phone,

      api.api_email_marketing_state,
      api.api_email_marketing_opt_in_level,
      staging.staging_accepts_email_marketing,

      api.api_sms_marketing_state,
      api.api_sms_marketing_opt_in_level,
      staging.staging_accepts_sms_marketing,

      api.api_customer_state,
      api.api_verified_email,

      api.api_tax_exempt,
      staging.staging_tax_exempt,
      staging.staging_tax_exempt_bool,

      api.api_number_of_orders,
      staging.staging_total_orders,

      api.api_amount_spent,
      api.api_amount_spent_currency,
      staging.staging_total_spent,

      api.api_customer_created_at,
      api.api_customer_updated_at,

      api.api_note,
      staging.staging_note,

      api.api_tags_json,
      staging.staging_tags,

      api.api_default_address_company,
      api.api_default_address_address1,
      api.api_default_address_address2,
      api.api_default_address_city,
      api.api_default_address_province_code,
      api.api_default_address_country_code,
      api.api_default_address_zip,
      api.api_default_address_phone,

      staging.staging_default_address_company,
      staging.staging_default_address_address1,
      staging.staging_default_address_address2,
      staging.staging_default_address_city,
      staging.staging_default_address_province_code,
      staging.staging_default_address_country_code,
      staging.staging_default_address_zip,
      staging.staging_default_address_phone

    FROM api_customers AS api
    FULL OUTER JOIN staging_customers AS staging
      ON api.api_shopify_customer_id = staging.staging_shopify_customer_id
  )

SELECT
  joined.unified_shopify_customer_id,

  joined.shopify_customer_graphql_id,
  joined.api_shopify_customer_id,
  joined.staging_shopify_customer_id,

  raw.raw_shopify_customer_id,
  dim.dim_shopify_customer_id,

  joined.api_email,
  joined.staging_customer_email,
  raw.raw_email,
  dim.dim_customer_email,

  joined.api_normalized_email,
  joined.staging_normalized_email,
  raw.raw_normalized_email,
  dim.dim_normalized_email,

  joined.api_first_name,
  joined.api_last_name,
  joined.api_display_name,
  joined.staging_first_name,
  joined.staging_last_name,
  raw.raw_first_name,
  raw.raw_last_name,
  dim.dim_first_name,
  dim.dim_last_name,

  joined.api_phone,
  joined.staging_phone,
  raw.raw_phone,

  joined.api_email_marketing_state,
  joined.api_email_marketing_opt_in_level,
  joined.staging_accepts_email_marketing,
  raw.raw_accepts_email_marketing,
  dim.dim_accepts_email_marketing,

  joined.api_sms_marketing_state,
  joined.api_sms_marketing_opt_in_level,
  joined.staging_accepts_sms_marketing,
  raw.raw_accepts_sms_marketing,
  dim.dim_accepts_sms_marketing,

  joined.api_customer_state,
  joined.api_verified_email,

  joined.api_tax_exempt,
  joined.staging_tax_exempt,
  joined.staging_tax_exempt_bool,
  raw.raw_tax_exempt,
  dim.dim_tax_exempt,

  joined.api_number_of_orders,
  joined.staging_total_orders,
  raw.raw_total_orders,
  dim.dim_total_orders,
  dim.lifetime_order_count_from_orders,

  joined.api_amount_spent,
  joined.api_amount_spent_currency,
  joined.staging_total_spent,
  raw.raw_total_spent,
  dim.dim_total_spent,

  ROUND(joined.api_amount_spent - joined.staging_total_spent, 2)
    AS api_vs_staging_amount_spent_diff,

  joined.api_number_of_orders - joined.staging_total_orders
    AS api_vs_staging_total_orders_diff,

  joined.api_customer_created_at,
  joined.api_customer_updated_at,
  dim.first_order_at,
  dim.last_order_at,

  joined.api_note,
  joined.staging_note,
  raw.raw_note,

  joined.api_tags_json,
  joined.staging_tags,
  raw.raw_tags,

  joined.api_default_address_company,
  joined.api_default_address_address1,
  joined.api_default_address_address2,
  joined.api_default_address_city,
  joined.api_default_address_province_code,
  joined.api_default_address_country_code,
  joined.api_default_address_zip,
  joined.api_default_address_phone,

  joined.staging_default_address_company,
  joined.staging_default_address_address1,
  joined.staging_default_address_address2,
  joined.staging_default_address_city,
  joined.staging_default_address_province_code,
  joined.staging_default_address_country_code,
  joined.staging_default_address_zip,
  joined.staging_default_address_phone,

  raw.raw_default_address_company,
  raw.raw_default_address_address1,
  raw.raw_default_address_address2,
  raw.raw_default_address_city,
  raw.raw_default_address_province_code,
  raw.raw_default_address_country_code,
  raw.raw_default_address_zip,
  raw.raw_default_address_phone,

  dim.dim_default_address_city,
  dim.dim_default_address_province_code,
  dim.dim_default_address_country_code,
  dim.dim_default_address_zip,

  CASE
    WHEN joined.api_shopify_customer_id IS NULL THEN 'staging_only'
    WHEN joined.staging_shopify_customer_id IS NULL THEN 'api_only'
    WHEN joined.api_normalized_email IS NULL
      AND joined.staging_normalized_email IS NULL
      THEN 'matched_by_legacy_both_missing_email'
    WHEN joined.api_normalized_email IS NULL
      THEN 'matched_by_legacy_api_missing_email'
    WHEN joined.staging_normalized_email IS NULL
      THEN 'matched_by_legacy_staging_missing_email'
    WHEN joined.api_normalized_email = joined.staging_normalized_email
      AND dim.dim_shopify_customer_id IS NOT NULL
      THEN 'matched_by_legacy_email_dim'
    WHEN joined.api_normalized_email = joined.staging_normalized_email
      AND dim.dim_shopify_customer_id IS NULL
      THEN 'matched_by_legacy_email_missing_dim'
    WHEN joined.api_normalized_email != joined.staging_normalized_email
      THEN 'matched_by_legacy_email_differs'
    ELSE 'matched_by_legacy_other'
  END AS reconciliation_status,

  CASE
    WHEN joined.api_shopify_customer_id IS NULL THEN 'staging_only_no_api_email_compare'
    WHEN joined.staging_shopify_customer_id IS NULL THEN 'api_only_no_staging_email_compare'
    WHEN joined.api_normalized_email IS NULL
      AND joined.staging_normalized_email IS NULL
      THEN 'both_missing_email'
    WHEN joined.api_normalized_email IS NULL THEN 'api_missing_email'
    WHEN joined.staging_normalized_email IS NULL THEN 'staging_missing_email'
    WHEN joined.api_normalized_email = joined.staging_normalized_email
      THEN 'email_matches_staging'
    ELSE 'email_differs_from_staging'
  END AS email_reconciliation_status,

  CASE
    WHEN joined.api_shopify_customer_id IS NULL THEN 'staging_only_no_api_orders_compare'
    WHEN joined.staging_shopify_customer_id IS NULL THEN 'api_only_no_staging_orders_compare'
    WHEN joined.api_number_of_orders IS NULL THEN 'missing_api_total_orders'
    WHEN joined.staging_total_orders IS NULL THEN 'missing_staging_total_orders'
    WHEN joined.api_number_of_orders = joined.staging_total_orders
      THEN 'total_orders_matches_staging'
    ELSE 'total_orders_differs_from_staging'
  END AS total_orders_reconciliation_status,

  CASE
    WHEN joined.api_shopify_customer_id IS NULL THEN 'staging_only_no_api_spend_compare'
    WHEN joined.staging_shopify_customer_id IS NULL THEN 'api_only_no_staging_spend_compare'
    WHEN joined.api_amount_spent IS NULL THEN 'missing_api_amount_spent'
    WHEN joined.staging_total_spent IS NULL THEN 'missing_staging_total_spent'
    WHEN ROUND(joined.api_amount_spent - joined.staging_total_spent, 2) = 0
      THEN 'amount_spent_matches_staging'
    ELSE 'amount_spent_differs_from_staging'
  END AS amount_spent_reconciliation_status,

  CASE
    WHEN joined.api_shopify_customer_id IS NULL THEN 'staging_only_no_api_tax_compare'
    WHEN joined.staging_shopify_customer_id IS NULL THEN 'api_only_no_staging_tax_compare'
    WHEN joined.api_tax_exempt IS NULL THEN 'missing_api_tax_exempt'
    WHEN joined.staging_tax_exempt_bool IS NULL THEN 'missing_or_unrecognized_staging_tax_exempt'
    WHEN joined.api_tax_exempt = joined.staging_tax_exempt_bool
      THEN 'tax_exempt_matches_staging'
    ELSE 'tax_exempt_differs_from_staging'
  END AS tax_exempt_reconciliation_status

FROM api_staging_joined AS joined
LEFT JOIN raw_customers AS raw
  ON joined.unified_shopify_customer_id = raw.raw_shopify_customer_id
LEFT JOIN dim_customers AS dim
  ON joined.unified_shopify_customer_id = dim.dim_shopify_customer_id;