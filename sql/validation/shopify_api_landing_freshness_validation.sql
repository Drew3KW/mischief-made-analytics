-- File: sql/validation/shopify_api_landing_freshness_validation.sql
-- Purpose:
-- Validate that Shopify API landing tables were refreshed recently and contain rows.
--
-- Intended use:
-- - Run after Shopify API landing DAGs complete.
-- - Used as an Airflow validation gate in mm_shopify_api_canonical_refresh_mvp.
--
-- Important notes:
-- - FAIL rows are blockers.
-- - INFO rows are descriptive.
-- - The freshness threshold is intentionally generous for local Airflow runs.

WITH config AS (
  SELECT
    360 AS max_allowed_age_minutes
),

landing_tables AS (
  SELECT
    'orders' AS landing_table,
    COUNT(*) AS row_count,
    MAX(api_extracted_at) AS latest_api_extracted_at
  FROM `mischief-made-analytics.raw_load.shopify_orders_api_latest`

  UNION ALL

  SELECT
    'order_line_items' AS landing_table,
    COUNT(*) AS row_count,
    MAX(api_extracted_at) AS latest_api_extracted_at
  FROM `mischief-made-analytics.raw_load.shopify_order_line_items_api_latest`

  UNION ALL

  SELECT
    'customers' AS landing_table,
    COUNT(*) AS row_count,
    MAX(api_extracted_at) AS latest_api_extracted_at
  FROM `mischief-made-analytics.raw_load.shopify_customers_api_latest`

  UNION ALL

  SELECT
    'products' AS landing_table,
    COUNT(*) AS row_count,
    MAX(api_extracted_at) AS latest_api_extracted_at
  FROM `mischief-made-analytics.raw_load.shopify_products_api_latest`

  UNION ALL

  SELECT
    'product_variants' AS landing_table,
    COUNT(*) AS row_count,
    MAX(api_extracted_at) AS latest_api_extracted_at
  FROM `mischief-made-analytics.raw_load.shopify_product_variants_api_latest`
),

landing_with_age AS (
  SELECT
    landing_table,
    row_count,
    latest_api_extracted_at,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), latest_api_extracted_at, MINUTE) AS extract_age_minutes
  FROM landing_tables
),

checks AS (
  SELECT
    CONCAT('api_landing_', landing_table, '_rows_present') AS check_name,
    row_count AS result_value,
    1 AS expected_value,
    IF(row_count > 0, 'PASS', 'FAIL') AS check_status,
    CONCAT('Landing table row count for ', landing_table, '.') AS notes
  FROM landing_with_age

  UNION ALL

  SELECT
    CONCAT('api_landing_', landing_table, '_has_extract_timestamp') AS check_name,
    IF(latest_api_extracted_at IS NULL, 0, 1) AS result_value,
    1 AS expected_value,
    IF(latest_api_extracted_at IS NOT NULL, 'PASS', 'FAIL') AS check_status,
    CONCAT('Latest api_extracted_at for ', landing_table, ': ', CAST(latest_api_extracted_at AS STRING)) AS notes
  FROM landing_with_age

  UNION ALL

  SELECT
    CONCAT('api_landing_', landing_table, '_freshness_minutes') AS check_name,
    extract_age_minutes AS result_value,
    config.max_allowed_age_minutes AS expected_value,
    IF(
      latest_api_extracted_at IS NOT NULL
      AND extract_age_minutes <= config.max_allowed_age_minutes,
      'PASS',
      'FAIL'
    ) AS check_status,
    CONCAT(
      'Latest extract for ',
      landing_table,
      ' should be within ',
      CAST(config.max_allowed_age_minutes AS STRING),
      ' minutes. Latest extract: ',
      CAST(latest_api_extracted_at AS STRING)
    ) AS notes
  FROM landing_with_age
  CROSS JOIN config

  UNION ALL

  SELECT
    'api_landing_latest_extract_utc' AS check_name,
    CAST(NULL AS INT64) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    CONCAT(
      'Latest landing extract timestamp across all API landing tables: ',
      CAST(MAX(latest_api_extracted_at) AS STRING)
    ) AS notes
  FROM landing_with_age
)

SELECT
  check_name,
  result_value,
  expected_value,
  check_status,
  notes
FROM checks
ORDER BY
  CASE check_status
    WHEN 'FAIL' THEN 1
    WHEN 'REVIEW' THEN 2
    WHEN 'PASS' THEN 3
    ELSE 4
  END,
  check_name;