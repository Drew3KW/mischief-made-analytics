-- File: sql/validation/shopify_api_raw_candidates_validation.sql
-- Purpose:
-- Validate Shopify API shadow raw candidate tables created in raw_load.
--
-- Important notes:
-- - These checks do not modify canonical raw tables.
-- - These checks do not replace the CSV ingestion path.
-- - These checks validate candidate shape and basic compatibility before any
--   future canonical raw rebuild work.

WITH product_candidate AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.shopify_products_api_raw_candidate`
),

api_variants AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.shopify_product_variants_api_latest`
),

customer_candidate AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.shopify_customers_api_raw_candidate`
),

api_customers AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.shopify_customers_api_latest`
),

order_candidate AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.shopify_orders_api_raw_candidate`
),

api_line_items AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.shopify_order_line_items_api_latest`
),

staging_products AS (
  SELECT sku
  FROM `mischief-made-analytics.staging.stg_shopify_products`
),

staging_customers AS (
  SELECT shopify_customer_id, customer_email
  FROM `mischief-made-analytics.staging.stg_shopify_customers`
),

staging_orders AS (
  SELECT shopify_order_id, order_number
  FROM `mischief-made-analytics.staging.stg_shopify_orders`
),

checks AS (
  SELECT
    'product_candidate_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
    'Product raw candidate should not be empty.' AS notes
  FROM product_candidate

  UNION ALL

  SELECT
    'product_candidate_rows_match_api_variants' AS check_name,
    (SELECT COUNT(*) FROM product_candidate) AS result_value,
    (SELECT COUNT(*) FROM api_variants) AS expected_value,
    IF(
      (SELECT COUNT(*) FROM product_candidate) = (SELECT COUNT(*) FROM api_variants),
      'PASS',
      'FAIL'
    ) AS check_status,
    'Product raw candidate should remain one row per API product variant.' AS notes

  UNION ALL

  SELECT
    'product_candidate_duplicate_nonblank_skus' AS check_name,
    COUNT(*) - COUNT(DISTINCT LOWER(TRIM(variant_sku))) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Duplicate nonblank SKUs are informational because catalog duplicates may exist.' AS notes
  FROM product_candidate
  WHERE NULLIF(TRIM(variant_sku), '') IS NOT NULL

  UNION ALL

  SELECT
    'product_candidate_blank_sku_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Blank SKU rows are allowed in raw candidate, but staging filters them out.' AS notes
  FROM product_candidate
  WHERE NULLIF(TRIM(variant_sku), '') IS NULL

  UNION ALL

  SELECT
    'product_candidate_overlap_with_staging_skus' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Nonblank candidate SKUs that currently appear in staging products.' AS notes
  FROM (
    SELECT DISTINCT LOWER(TRIM(variant_sku)) AS sku
    FROM product_candidate
    WHERE NULLIF(TRIM(variant_sku), '') IS NOT NULL
  ) AS candidate
  INNER JOIN (
    SELECT DISTINCT LOWER(TRIM(sku)) AS sku
    FROM staging_products
    WHERE NULLIF(TRIM(sku), '') IS NOT NULL
  ) AS staging
    USING (sku)

  UNION ALL

  SELECT
    'customer_candidate_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
    'Customer raw candidate should not be empty.' AS notes
  FROM customer_candidate

  UNION ALL

  SELECT
    'customer_candidate_rows_match_api_customers' AS check_name,
    (SELECT COUNT(*) FROM customer_candidate) AS result_value,
    (SELECT COUNT(*) FROM api_customers) AS expected_value,
    IF(
      (SELECT COUNT(*) FROM customer_candidate) = (SELECT COUNT(*) FROM api_customers),
      'PASS',
      'FAIL'
    ) AS check_status,
    'Customer raw candidate should remain one row per API customer.' AS notes

  UNION ALL

  SELECT
    'customer_candidate_duplicate_customer_ids' AS check_name,
    COUNT(*) - COUNT(DISTINCT customer_id) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) - COUNT(DISTINCT customer_id) = 0, 'PASS', 'FAIL') AS check_status,
    'Customer raw candidate should not have duplicate nonnull customer IDs.' AS notes
  FROM customer_candidate
  WHERE customer_id IS NOT NULL

  UNION ALL

  SELECT
    'customer_candidate_missing_email_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Customers missing email are allowed and should match prior API landing expectations.' AS notes
  FROM customer_candidate
  WHERE NULLIF(TRIM(email), '') IS NULL

  UNION ALL

  SELECT
    'customer_candidate_overlap_with_staging_customer_ids' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Candidate customers whose customer_id appears in current staging customers.' AS notes
  FROM customer_candidate AS candidate
  INNER JOIN staging_customers AS staging
    ON SAFE_CAST(candidate.customer_id AS INT64) = staging.shopify_customer_id

  UNION ALL

  SELECT
    'order_candidate_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
    'Order raw candidate should not be empty.' AS notes
  FROM order_candidate

  UNION ALL

  SELECT
    'order_candidate_rows_match_api_line_items' AS check_name,
    (SELECT COUNT(*) FROM order_candidate) AS result_value,
    (SELECT COUNT(*) FROM api_line_items) AS expected_value,
    IF(
      (SELECT COUNT(*) FROM order_candidate) = (SELECT COUNT(*) FROM api_line_items),
      'PASS',
      'FAIL'
    ) AS check_status,
    'Order raw candidate should remain one row per API line item.' AS notes

  UNION ALL

  SELECT
    'order_candidate_missing_order_numbers' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Every candidate order line should have an order number.' AS notes
  FROM order_candidate
  WHERE `Name` IS NULL

  UNION ALL

  SELECT
    'order_candidate_created_at_parse_failures' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Candidate Created at values should parse with the current staging timestamp format.' AS notes
  FROM order_candidate
  WHERE `Created at` IS NOT NULL
    AND SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S %z', `Created at`) IS NULL

  UNION ALL

  SELECT
    'order_candidate_paid_at_parse_failures' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Candidate Paid at values should parse with the current staging timestamp format.' AS notes
  FROM order_candidate
  WHERE `Paid at` IS NOT NULL
    AND SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S %z', `Paid at`) IS NULL

  UNION ALL

  SELECT
    'order_candidate_quantity_cast_failures' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Candidate Lineitem quantity values should cast to INT64.' AS notes
  FROM order_candidate
  WHERE `Lineitem quantity` IS NOT NULL
    AND SAFE_CAST(`Lineitem quantity` AS INT64) IS NULL

  UNION ALL

  SELECT
    'order_candidate_price_cast_failures' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Candidate Lineitem price values should cast to NUMERIC.' AS notes
  FROM order_candidate
  WHERE `Lineitem price` IS NOT NULL
    AND SAFE_CAST(`Lineitem price` AS NUMERIC) IS NULL

  UNION ALL

  SELECT
    'order_candidate_overlap_with_staging_orders' AS check_name,
    COUNT(DISTINCT candidate.`Name`) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Candidate order numbers that currently appear in staging orders.' AS notes
  FROM order_candidate AS candidate
  INNER JOIN staging_orders AS staging
    ON candidate.`Name` = staging.order_number
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