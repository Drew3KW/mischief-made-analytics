-- File: sql/validation/shopify_canonical_raw_replacement_validation.sql
-- Purpose:
-- Validate the first manual Shopify API-backed canonical raw replacement MVP.
--
-- Run this after:
-- 1. Running Shopify API landing DAGs
-- 2. Rebuilding API raw candidates
-- 3. Rebuilding hybrid raw candidates
-- 4. Backing up current canonical raw tables
-- 5. Replacing canonical raw from hybrid raw candidates
-- 6. Refreshing staging, marts, analysis, and standard validation outputs
--
-- Important notes:
-- - FAIL rows are blockers.
-- - INFO rows are descriptive.

WITH cutover AS (
  SELECT
    ANY_VALUE(_api_cutover_date) AS api_cutover_date
  FROM `mischief-made-analytics.raw_load.shopify_orders_hybrid_raw_candidate`
),

schema_differences AS (
  SELECT
    'products_raw_missing_from_backup_schema' AS difference_type,
    column_name,
    data_type
  FROM (
    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw_load.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'shopify_products_pre_api_replacement_backup_20260512'

    EXCEPT DISTINCT

    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'shopify_products'
  )

  UNION ALL

  SELECT
    'products_raw_extra_vs_backup_schema' AS difference_type,
    column_name,
    data_type
  FROM (
    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'shopify_products'

    EXCEPT DISTINCT

    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw_load.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'shopify_products_pre_api_replacement_backup_20260512'
  )

  UNION ALL

  SELECT
    'customers_raw_missing_from_backup_schema' AS difference_type,
    column_name,
    data_type
  FROM (
    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw_load.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'shopify_customers_pre_api_replacement_backup_20260512'

    EXCEPT DISTINCT

    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'shopify_customers'
  )

  UNION ALL

  SELECT
    'customers_raw_extra_vs_backup_schema' AS difference_type,
    column_name,
    data_type
  FROM (
    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'shopify_customers'

    EXCEPT DISTINCT

    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw_load.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'shopify_customers_pre_api_replacement_backup_20260512'
  )

  UNION ALL

  SELECT
    'orders_raw_missing_from_backup_schema' AS difference_type,
    column_name,
    data_type
  FROM (
    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw_load.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'shopify_orders_pre_api_replacement_backup_20260512'

    EXCEPT DISTINCT

    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'shopify_orders'
  )

  UNION ALL

  SELECT
    'orders_raw_extra_vs_backup_schema' AS difference_type,
    column_name,
    data_type
  FROM (
    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'shopify_orders'

    EXCEPT DISTINCT

    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw_load.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'shopify_orders_pre_api_replacement_backup_20260512'
  )
),

product_raw AS (
  SELECT *
  FROM `mischief-made-analytics.raw.shopify_products`
),

product_candidate AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.shopify_products_hybrid_raw_candidate`
),

customer_raw AS (
  SELECT *
  FROM `mischief-made-analytics.raw.shopify_customers`
),

customer_candidate AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.shopify_customers_hybrid_raw_candidate`
),

order_raw AS (
  SELECT *
  FROM `mischief-made-analytics.raw.shopify_orders`
),

order_candidate AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.shopify_orders_hybrid_raw_candidate`
),

order_raw_fingerprints AS (
  SELECT
    TO_HEX(
      MD5(
        CONCAT(
          COALESCE(TRIM(`Name`), ''),
          '||',
          COALESCE(TRIM(`Lineitem sku`), ''),
          '||',
          COALESCE(TRIM(`Lineitem name`), ''),
          '||',
          COALESCE(TRIM(`Lineitem quantity`), ''),
          '||',
          COALESCE(TRIM(`Lineitem price`), ''),
          '||',
          COALESCE(TRIM(`Created at`), ''),
          '||',
          COALESCE(LOWER(TRIM(`Email`)), '')
        )
      )
    ) AS line_item_fingerprint
  FROM order_raw
),

order_candidate_fingerprints AS (
  SELECT
    _hybrid_source,
    _api_cutover_date,
    TO_HEX(
      MD5(
        CONCAT(
          COALESCE(TRIM(`Name`), ''),
          '||',
          COALESCE(TRIM(`Lineitem sku`), ''),
          '||',
          COALESCE(TRIM(`Lineitem name`), ''),
          '||',
          COALESCE(TRIM(`Lineitem quantity`), ''),
          '||',
          COALESCE(TRIM(`Lineitem price`), ''),
          '||',
          COALESCE(TRIM(`Created at`), ''),
          '||',
          COALESCE(LOWER(TRIM(`Email`)), '')
        )
      )
    ) AS line_item_fingerprint
  FROM order_candidate
),

api_forward_candidate_fingerprints AS (
  SELECT DISTINCT
    line_item_fingerprint
  FROM order_candidate_fingerprints
  WHERE _hybrid_source = 'api_forward_on_or_after_cutover'
),

checks AS (
  SELECT
    'raw_schema_matches_pre_replacement_backup_schema' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Canonical raw schemas should remain aligned with their pre-replacement backup schemas.' AS notes
  FROM schema_differences

  UNION ALL

  SELECT
    'product_raw_rows_match_hybrid_candidate' AS check_name,
    (SELECT COUNT(*) FROM product_raw) - (SELECT COUNT(*) FROM product_candidate) AS result_value,
    0 AS expected_value,
    IF(
      (SELECT COUNT(*) FROM product_raw) = (SELECT COUNT(*) FROM product_candidate),
      'PASS',
      'FAIL'
    ) AS check_status,
    'Post-replacement raw.shopify_products row count should match the hybrid raw candidate.' AS notes

  UNION ALL

  SELECT
    'customer_raw_rows_match_hybrid_candidate' AS check_name,
    (SELECT COUNT(*) FROM customer_raw) - (SELECT COUNT(*) FROM customer_candidate) AS result_value,
    0 AS expected_value,
    IF(
      (SELECT COUNT(*) FROM customer_raw) = (SELECT COUNT(*) FROM customer_candidate),
      'PASS',
      'FAIL'
    ) AS check_status,
    'Post-replacement raw.shopify_customers row count should match the hybrid raw candidate.' AS notes

  UNION ALL

  SELECT
    'order_raw_rows_match_hybrid_candidate' AS check_name,
    (SELECT COUNT(*) FROM order_raw) - (SELECT COUNT(*) FROM order_candidate) AS result_value,
    0 AS expected_value,
    IF(
      (SELECT COUNT(*) FROM order_raw) = (SELECT COUNT(*) FROM order_candidate),
      'PASS',
      'FAIL'
    ) AS check_status,
    'Post-replacement raw.shopify_orders row count should match the hybrid raw candidate.' AS notes

  UNION ALL

  SELECT
    'product_raw_missing_candidate_skus' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Every nonblank product SKU in the hybrid candidate should exist in canonical raw after replacement.' AS notes
  FROM (
    SELECT DISTINCT LOWER(TRIM(variant_sku)) AS sku_key
    FROM product_candidate
    WHERE NULLIF(TRIM(variant_sku), '') IS NOT NULL
  ) AS candidate_skus
  LEFT JOIN (
    SELECT DISTINCT LOWER(TRIM(variant_sku)) AS sku_key
    FROM product_raw
    WHERE NULLIF(TRIM(variant_sku), '') IS NOT NULL
  ) AS raw_skus
  USING (sku_key)
  WHERE raw_skus.sku_key IS NULL

  UNION ALL

  SELECT
    'customer_raw_missing_candidate_customer_ids' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Every nonblank customer ID in the hybrid candidate should exist in canonical raw after replacement.' AS notes
  FROM (
    SELECT DISTINCT TRIM(customer_id) AS customer_id_key
    FROM customer_candidate
    WHERE NULLIF(TRIM(customer_id), '') IS NOT NULL
  ) AS candidate_customers
  LEFT JOIN (
    SELECT DISTINCT TRIM(customer_id) AS customer_id_key
    FROM customer_raw
    WHERE NULLIF(TRIM(customer_id), '') IS NOT NULL
  ) AS raw_customers
  USING (customer_id_key)
  WHERE raw_customers.customer_id_key IS NULL

  UNION ALL

  SELECT
    'order_raw_missing_candidate_line_item_fingerprints' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Every hybrid candidate order line item fingerprint should exist in canonical raw after replacement.' AS notes
  FROM (
    SELECT DISTINCT line_item_fingerprint
    FROM order_candidate_fingerprints
  ) AS candidate_items
  LEFT JOIN (
    SELECT DISTINCT line_item_fingerprint
    FROM order_raw_fingerprints
  ) AS raw_items
  USING (line_item_fingerprint)
  WHERE raw_items.line_item_fingerprint IS NULL

  UNION ALL

  SELECT
    'order_raw_api_forward_items_included' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Every API-forward order line item fingerprint should exist in canonical raw after replacement.' AS notes
  FROM api_forward_candidate_fingerprints AS api_items
  LEFT JOIN (
    SELECT DISTINCT line_item_fingerprint
    FROM order_raw_fingerprints
  ) AS raw_items
  USING (line_item_fingerprint)
  WHERE raw_items.line_item_fingerprint IS NULL

  UNION ALL

  SELECT
    'product_staging_rows_after_refresh' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
    'Production product staging should rebuild successfully after replacement.' AS notes
  FROM `mischief-made-analytics.staging.stg_shopify_products`

  UNION ALL

  SELECT
    'customer_staging_rows_after_refresh' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
    'Production customer staging should rebuild successfully after replacement.' AS notes
  FROM `mischief-made-analytics.staging.stg_shopify_customers`

  UNION ALL

  SELECT
    'order_item_staging_rows_after_refresh' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
    'Production order item staging should rebuild successfully after replacement.' AS notes
  FROM `mischief-made-analytics.staging.stg_shopify_order_items`

  UNION ALL

  SELECT
    'order_staging_rows_after_refresh' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
    'Production order staging should rebuild successfully after replacement.' AS notes
  FROM `mischief-made-analytics.staging.stg_shopify_orders`

  UNION ALL

  SELECT
    'order_api_cutover_date' AS check_name,
    CAST(NULL AS INT64) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    CONCAT('Derived API cutover date: ', CAST((SELECT api_cutover_date FROM cutover) AS STRING)) AS notes

  UNION ALL

  SELECT
    'product_raw_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Post-replacement raw.shopify_products row count.' AS notes
  FROM product_raw

  UNION ALL

  SELECT
    'customer_raw_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Post-replacement raw.shopify_customers row count.' AS notes
  FROM customer_raw

  UNION ALL

  SELECT
    'order_raw_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Post-replacement raw.shopify_orders row count.' AS notes
  FROM order_raw

  UNION ALL

  SELECT
    'order_raw_api_forward_item_count' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'API-forward order line items present in canonical raw after replacement.' AS notes
  FROM api_forward_candidate_fingerprints
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