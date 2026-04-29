-- sql/validation/shopify_api_csv_product_reconciliation_validation.sql
-- Purpose:
-- Validate the Shopify API vs CSV product reconciliation view.
--
-- Notes:
-- - This is comparison-only validation.
-- - Some checks are informational because API and CSV shapes are not expected
--   to match perfectly yet.

WITH
  reconciliation AS (
    SELECT *
    FROM `mischief-made-analytics.marts.anl_shopify_api_csv_product_reconciliation`
  ),

  status_counts AS (
    SELECT
      reconciliation_status,
      COUNT(*) AS row_count
    FROM reconciliation
    GROUP BY reconciliation_status
  ),

  price_status_counts AS (
    SELECT
      price_reconciliation_status,
      COUNT(*) AS row_count
    FROM reconciliation
    GROUP BY price_reconciliation_status
  ),

  inventory_status_counts AS (
    SELECT
      inventory_reconciliation_status,
      COUNT(*) AS row_count
    FROM reconciliation
    GROUP BY inventory_reconciliation_status
  ),

  checks AS (
    SELECT
      'reconciliation_view_row_count' AS check_name,
      COUNT(*) AS result_value,
      2436 AS expected_value,
      IF(COUNT(*) = 2436, 'PASS', 'REVIEW') AS check_status,
      'The reconciliation view should currently have one row per API product variant.' AS notes
    FROM reconciliation

    UNION ALL

    SELECT
      'duplicate_api_variant_graphql_ids' AS check_name,
      COUNT(*) - COUNT(DISTINCT shopify_product_variant_graphql_id) AS result_value,
      0 AS expected_value,
      IF(
        COUNT(*) - COUNT(DISTINCT shopify_product_variant_graphql_id) = 0,
        'PASS',
        'FAIL'
      ) AS check_status,
      'Each API product variant GraphQL ID should appear once in the reconciliation view.' AS notes
    FROM reconciliation

    UNION ALL

    SELECT
      'api_variants_missing_sku' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
      'API variants without SKUs may be legitimate, but need review before any canonical raw rebuild.' AS notes
    FROM reconciliation
    WHERE reconciliation_status = 'api_variant_missing_sku'

    UNION ALL

    SELECT
      'api_only_variant_rows' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
      'API variants not found in the current CSV-derived product data need review.' AS notes
    FROM reconciliation
    WHERE reconciliation_status = 'api_only'

    UNION ALL

    SELECT
      'matched_api_csv_staging_dim_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'API variants matched to CSV raw, staging, and dim_products by normalized SKU.' AS notes
    FROM reconciliation
    WHERE reconciliation_status = 'matched_api_csv_staging_dim'

    UNION ALL

    SELECT
      'price_differs_from_staging_rows' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
      'API variant price differs from staging price where SKU matches.' AS notes
    FROM reconciliation
    WHERE price_reconciliation_status = 'price_differs_from_staging'

    UNION ALL

    SELECT
      'inventory_differs_from_staging_rows' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      'INFO' AS check_status,
      'Inventory can change frequently, so differences are informational at this stage.' AS notes
    FROM reconciliation
    WHERE inventory_reconciliation_status = 'inventory_differs_from_staging'
  )

SELECT
  check_name,
  result_value,
  expected_value,
  check_status,
  notes
FROM checks

UNION ALL

SELECT
  CONCAT('reconciliation_status__', reconciliation_status) AS check_name,
  row_count AS result_value,
  CAST(NULL AS INT64) AS expected_value,
  'INFO' AS check_status,
  'Distribution of reconciliation statuses.' AS notes
FROM status_counts

UNION ALL

SELECT
  CONCAT('price_status__', price_reconciliation_status) AS check_name,
  row_count AS result_value,
  CAST(NULL AS INT64) AS expected_value,
  'INFO' AS check_status,
  'Distribution of price reconciliation statuses.' AS notes
FROM price_status_counts

UNION ALL

SELECT
  CONCAT('inventory_status__', inventory_reconciliation_status) AS check_name,
  row_count AS result_value,
  CAST(NULL AS INT64) AS expected_value,
  'INFO' AS check_status,
  'Distribution of inventory reconciliation statuses.' AS notes
FROM inventory_status_counts

ORDER BY
  CASE check_status
    WHEN 'FAIL' THEN 1
    WHEN 'REVIEW' THEN 2
    WHEN 'PASS' THEN 3
    ELSE 4
  END,
  check_name;