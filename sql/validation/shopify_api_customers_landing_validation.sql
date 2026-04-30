-- sql/validation/shopify_api_customers_landing_validation.sql
-- Purpose:
-- Validate the isolated Shopify API customers landing table created by
-- the customers API landing MVP.
--
-- Notes:
-- - These checks do not modify canonical raw tables.
-- - These checks do not replace the CSV ingestion path.
-- - These checks support future API-vs-CSV customer reconciliation.

WITH
  api_customers AS (
    SELECT
      shopify_customer_graphql_id,
      SAFE_CAST(legacy_resource_id AS INT64) AS legacy_resource_id,
      LOWER(TRIM(email)) AS normalized_email,
      amount_spent,
      number_of_orders
    FROM `mischief-made-analytics.raw_load.shopify_customers_api_latest`
  ),

  raw_customers AS (
    SELECT
      SAFE_CAST(customer_id AS INT64) AS shopify_customer_id,
      LOWER(TRIM(email)) AS normalized_email,
      SAFE_CAST(NULLIF(TRIM(total_spent), '') AS NUMERIC) AS total_spent,
      SAFE_CAST(NULLIF(TRIM(total_orders), '') AS INT64) AS total_orders
    FROM `mischief-made-analytics.raw.shopify_customers`
  ),

  staging_customers AS (
    SELECT
      shopify_customer_id,
      LOWER(TRIM(customer_email)) AS normalized_email,
      total_spent,
      total_orders
    FROM `mischief-made-analytics.staging.stg_shopify_customers`
  ),

  dim_customers AS (
    SELECT
      shopify_customer_id,
      LOWER(TRIM(customer_email)) AS normalized_email,
      total_spent,
      total_orders
    FROM `mischief-made-analytics.marts.dim_customers`
  ),

  checks AS (
    SELECT
      'api_customer_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
      'API customer landing table should not be empty.' AS notes
    FROM api_customers

    UNION ALL

    SELECT
      'api_duplicate_graphql_ids' AS check_name,
      COUNT(*) - COUNT(DISTINCT shopify_customer_graphql_id) AS result_value,
      0 AS expected_value,
      IF(
        COUNT(*) - COUNT(DISTINCT shopify_customer_graphql_id) = 0,
        'PASS',
        'FAIL'
      ) AS check_status,
      'Each API customer GraphQL ID should appear once.' AS notes
    FROM api_customers

    UNION ALL

    SELECT
      'api_duplicate_legacy_resource_ids' AS check_name,
      COUNT(*) - COUNT(DISTINCT legacy_resource_id) AS result_value,
      0 AS expected_value,
      IF(
        COUNT(*) - COUNT(DISTINCT legacy_resource_id) = 0,
        'PASS',
        'FAIL'
      ) AS check_status,
      'Each API customer legacy resource ID should appear once.' AS notes
    FROM api_customers
    WHERE legacy_resource_id IS NOT NULL

    UNION ALL

    SELECT
      'api_missing_legacy_resource_ids' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
      'API customers should have legacy resource IDs for CSV reconciliation.' AS notes
    FROM api_customers
    WHERE legacy_resource_id IS NULL

    UNION ALL

    SELECT
      'api_customers_missing_email' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
      'Customers without email may be legitimate but need review for customer-key strategy.' AS notes
    FROM api_customers
    WHERE normalized_email IS NULL

    UNION ALL

    SELECT
      'raw_csv_customer_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Current canonical CSV-derived raw customer rows.' AS notes
    FROM raw_customers

    UNION ALL

    SELECT
      'staging_customer_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Current staging customer rows.' AS notes
    FROM staging_customers

    UNION ALL

    SELECT
      'dim_customer_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Current customer dimension rows.' AS notes
    FROM dim_customers

    UNION ALL

    SELECT
      'api_legacy_id_overlap_with_staging' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'API customers whose legacy resource ID matches staging.shopify_customer_id.' AS notes
    FROM api_customers AS api
    INNER JOIN staging_customers AS staging
      ON api.legacy_resource_id = staging.shopify_customer_id

    UNION ALL

    SELECT
      'api_email_overlap_with_staging' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'API customers whose normalized email matches staging.customer_email.' AS notes
    FROM api_customers AS api
    INNER JOIN staging_customers AS staging
      ON api.normalized_email = staging.normalized_email
    WHERE api.normalized_email IS NOT NULL

    UNION ALL

    SELECT
      'api_email_overlap_with_dim_customers' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'API customers whose normalized email matches dim_customers.customer_email.' AS notes
    FROM api_customers AS api
    INNER JOIN dim_customers AS dim
      ON api.normalized_email = dim.normalized_email
    WHERE api.normalized_email IS NOT NULL
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