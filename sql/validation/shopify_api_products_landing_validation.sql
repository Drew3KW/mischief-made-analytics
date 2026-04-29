-- File: sql/validation/shopify_api_products_landing_validation.sql
-- Purpose:
-- Validate the isolated Shopify API products/variants landing tables created
-- by the Milestone 28 API landing MVP.
--
-- Notes:
-- - These checks do not modify canonical raw tables.
-- - These checks do not replace the CSV ingestion path.
-- - These checks are intended to support API-vs-CSV reconciliation before any
--   future canonical raw rebuild changes.

WITH
  api_products AS (
    SELECT
      shopify_product_graphql_id,
      legacy_resource_id,
      handle,
      title,
      status
    FROM `mischief-made-analytics.raw_load.shopify_products_api_latest`
  ),

  api_variants AS (
    SELECT
      shopify_product_variant_graphql_id,
      shopify_product_graphql_id,
      legacy_resource_id,
      sku,
      title,
      price,
      inventory_quantity
    FROM `mischief-made-analytics.raw_load.shopify_product_variants_api_latest`
  ),

  csv_raw_products AS (
    SELECT
      handle,
      variant_sku
    FROM `mischief-made-analytics.raw.shopify_products`
  ),

  staging_products AS (
    SELECT
      handle,
      sku
    FROM `mischief-made-analytics.staging.stg_shopify_products`
  ),

  dim_products AS (
    SELECT
      sku
    FROM `mischief-made-analytics.marts.dim_products`
  ),

  api_variant_skus AS (
    SELECT DISTINCT
      LOWER(TRIM(sku)) AS sku
    FROM api_variants
    WHERE NULLIF(TRIM(sku), '') IS NOT NULL
  ),

  csv_variant_skus AS (
    SELECT DISTINCT
      LOWER(TRIM(variant_sku)) AS sku
    FROM csv_raw_products
    WHERE NULLIF(TRIM(variant_sku), '') IS NOT NULL
  ),

  api_csv_sku_overlap AS (
    SELECT COUNT(*) AS overlap_count
    FROM api_variant_skus
    INNER JOIN csv_variant_skus
      USING (sku)
  ),

  checks AS (
    SELECT
      'api_product_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
      'API product landing table should not be empty.' AS notes
    FROM api_products

    UNION ALL

    SELECT
      'api_variant_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
      'API product variant landing table should not be empty.' AS notes
    FROM api_variants

    UNION ALL

    SELECT
      'api_product_duplicate_graphql_ids' AS check_name,
      COUNT(*) - COUNT(DISTINCT shopify_product_graphql_id) AS result_value,
      0 AS expected_value,
      IF(
        COUNT(*) - COUNT(DISTINCT shopify_product_graphql_id) = 0,
        'PASS',
        'FAIL'
      ) AS check_status,
      'Each API product GraphQL ID should appear once.' AS notes
    FROM api_products

    UNION ALL

    SELECT
      'api_variant_duplicate_graphql_ids' AS check_name,
      COUNT(*) - COUNT(DISTINCT shopify_product_variant_graphql_id) AS result_value,
      0 AS expected_value,
      IF(
        COUNT(*) - COUNT(DISTINCT shopify_product_variant_graphql_id) = 0,
        'PASS',
        'FAIL'
      ) AS check_status,
      'Each API product variant GraphQL ID should appear once.' AS notes
    FROM api_variants

    UNION ALL

    SELECT
      'api_variants_missing_parent_product_id' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
      'Each API variant should have a Shopify product parent ID from __parentId.' AS notes
    FROM api_variants
    WHERE shopify_product_graphql_id IS NULL

    UNION ALL

    SELECT
      'api_variant_orphan_parent_ids' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
      'Every API variant parent product ID should exist in the API product landing table.' AS notes
    FROM api_variants AS variants
    LEFT JOIN api_products AS products
      ON variants.shopify_product_graphql_id = products.shopify_product_graphql_id
    WHERE products.shopify_product_graphql_id IS NULL

    UNION ALL

    SELECT
      'csv_raw_product_variant_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Current canonical CSV-derived raw product rows, at product-variant/export grain.' AS notes
    FROM csv_raw_products

    UNION ALL

    SELECT
      'staging_product_rows_with_sku' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Current staging product rows after blank SKU filtering.' AS notes
    FROM staging_products

    UNION ALL

    SELECT
      'dim_product_sku_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Current product dimension rows after SKU deduplication.' AS notes
    FROM dim_products

    UNION ALL

    SELECT
      'api_variant_distinct_nonblank_skus' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Distinct nonblank SKUs present in the API variant landing table.' AS notes
    FROM api_variant_skus

    UNION ALL

    SELECT
      'csv_raw_distinct_nonblank_skus' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Distinct nonblank SKUs present in canonical CSV-derived raw products.' AS notes
    FROM csv_variant_skus

    UNION ALL

    SELECT
      'api_csv_distinct_sku_overlap' AS check_name,
      overlap_count AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Distinct nonblank SKUs shared by API variants and CSV-derived raw products.' AS notes
    FROM api_csv_sku_overlap
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
    WHEN 'PASS' THEN 2
    ELSE 3
  END,
  check_name;