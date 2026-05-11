-- File: sql/validation/shopify_hybrid_raw_candidate_validation.sql
-- Purpose:
-- Validate Shopify API hybrid raw candidate tables.
--
-- Important notes:
-- - These checks do not modify canonical raw tables.
-- - These checks do not modify production staging tables.
-- - REVIEW and INFO results are expected for source coverage differences.

WITH product_hybrid AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.shopify_products_hybrid_raw_candidate`
),

product_current_staging AS (
  SELECT *
  FROM `mischief-made-analytics.staging.stg_shopify_products`
),

customer_hybrid AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.shopify_customers_hybrid_raw_candidate`
),

customer_current_staging AS (
  SELECT *
  FROM `mischief-made-analytics.staging.stg_shopify_customers`
),

order_hybrid AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.shopify_orders_hybrid_raw_candidate`
),

order_current_raw AS (
  SELECT *
  FROM `mischief-made-analytics.raw.shopify_orders`
),

order_current_staging AS (
  SELECT *
  FROM `mischief-made-analytics.staging.stg_shopify_orders`
),

order_hybrid_parsed AS (
  SELECT
    *,
    SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S %z', `Created at`) AS created_at_ts,
    SAFE_CAST(`Lineitem quantity` AS INT64) AS quantity_int,
    SAFE_CAST(`Lineitem price` AS NUMERIC) AS lineitem_price_numeric,
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
    ) AS dedupe_fingerprint
  FROM order_hybrid
),

order_current_raw_parsed AS (
  SELECT
    *,
    SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S %z', `Created at`) AS created_at_ts
  FROM order_current_raw
),

order_hybrid_order_rollup AS (
  SELECT
    `Name` AS order_number,
    MAX(SAFE_CAST(`Id` AS INT64)) AS shopify_order_id,
    MAX(SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S %z', `Created at`)) AS created_at_ts,
    MAX(SAFE_CAST(`Total` AS NUMERIC)) AS order_total,
    SUM(SAFE_CAST(`Lineitem quantity` AS INT64)) AS total_items,
    COUNT(*) AS line_item_count,
    MAX(_hybrid_source) AS sample_hybrid_source
  FROM order_hybrid
  GROUP BY order_number
),

checks AS (
  SELECT
    'product_hybrid_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
    'Product hybrid raw candidate should not be empty.' AS notes
  FROM product_hybrid

  UNION ALL

  SELECT
    'product_hybrid_current_staging_skus_missing' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Every current staging product SKU should exist in the hybrid raw candidate.' AS notes
  FROM (
    SELECT DISTINCT LOWER(TRIM(sku)) AS sku_key
    FROM product_current_staging
    WHERE NULLIF(TRIM(sku), '') IS NOT NULL
  ) AS current_staging
  LEFT JOIN (
    SELECT DISTINCT LOWER(TRIM(variant_sku)) AS sku_key
    FROM product_hybrid
    WHERE NULLIF(TRIM(variant_sku), '') IS NOT NULL
  ) AS hybrid
    USING (sku_key)
  WHERE hybrid.sku_key IS NULL

  UNION ALL

  SELECT
    'product_hybrid_duplicate_nonblank_sku_keys' AS check_name,
    COUNT(*) - COUNT(DISTINCT LOWER(TRIM(variant_sku))) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Duplicate nonblank product SKU keys remain informational because catalog duplicate behavior already exists.' AS notes
  FROM product_hybrid
  WHERE NULLIF(TRIM(variant_sku), '') IS NOT NULL

  UNION ALL

  SELECT
    'product_hybrid_api_source_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Rows in the product hybrid candidate sourced from the API raw candidate.' AS notes
  FROM product_hybrid
  WHERE _hybrid_source = 'api_raw_candidate'

  UNION ALL

  SELECT
    'customer_hybrid_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
    'Customer hybrid raw candidate should not be empty.' AS notes
  FROM customer_hybrid

  UNION ALL

  SELECT
    'customer_hybrid_duplicate_customer_ids' AS check_name,
    COUNT(*) - COUNT(DISTINCT customer_id) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) - COUNT(DISTINCT customer_id) = 0, 'PASS', 'FAIL') AS check_status,
    'Customer hybrid raw candidate should not contain duplicate nonnull customer IDs.' AS notes
  FROM customer_hybrid
  WHERE NULLIF(TRIM(customer_id), '') IS NOT NULL

  UNION ALL

  SELECT
    'customer_hybrid_current_staging_ids_missing' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Every current staging customer ID should exist in the hybrid raw candidate.' AS notes
  FROM (
    SELECT DISTINCT shopify_customer_id
    FROM customer_current_staging
    WHERE shopify_customer_id IS NOT NULL
  ) AS current_staging
  LEFT JOIN (
    SELECT DISTINCT SAFE_CAST(customer_id AS INT64) AS shopify_customer_id
    FROM customer_hybrid
    WHERE SAFE_CAST(customer_id AS INT64) IS NOT NULL
  ) AS hybrid
    USING (shopify_customer_id)
  WHERE hybrid.shopify_customer_id IS NULL

  UNION ALL

  SELECT
    'customer_hybrid_missing_email_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Customers missing email are allowed and should remain visible for review.' AS notes
  FROM customer_hybrid
  WHERE NULLIF(TRIM(email), '') IS NULL

  UNION ALL

  SELECT
    'customer_hybrid_api_source_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Rows in the customer hybrid candidate sourced from the API raw candidate.' AS notes
  FROM customer_hybrid
  WHERE _hybrid_source = 'api_raw_candidate'

  UNION ALL

  SELECT
    'order_hybrid_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
    'Order hybrid raw candidate should not be empty.' AS notes
  FROM order_hybrid

  UNION ALL

  SELECT
    'order_hybrid_api_cutover_date' AS check_name,
    CAST(NULL AS INT64) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    CONCAT(
      'Derived API cutover date: ',
      CAST((SELECT ANY_VALUE(_api_cutover_date) FROM order_hybrid) AS STRING)
    ) AS notes

  UNION ALL

  SELECT
    'order_hybrid_duplicate_line_item_fingerprints' AS check_name,
    COUNT(*) - COUNT(DISTINCT dedupe_fingerprint) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) - COUNT(DISTINCT dedupe_fingerprint) = 0, 'PASS', 'FAIL') AS check_status,
    'Order hybrid raw candidate should not contain duplicate line-item fingerprints.' AS notes
  FROM order_hybrid_parsed

  UNION ALL

  SELECT
    'order_hybrid_missing_order_numbers' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Every hybrid order line should have an order number.' AS notes
  FROM order_hybrid
  WHERE NULLIF(TRIM(`Name`), '') IS NULL

  UNION ALL

  SELECT
    'order_hybrid_created_at_parse_failures' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Hybrid Created at values should parse with the current staging timestamp format.' AS notes
  FROM order_hybrid
  WHERE `Created at` IS NOT NULL
    AND SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S %z', `Created at`) IS NULL

  UNION ALL

  SELECT
    'order_hybrid_quantity_cast_failures' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Hybrid Lineitem quantity values should cast to INT64.' AS notes
  FROM order_hybrid
  WHERE `Lineitem quantity` IS NOT NULL
    AND SAFE_CAST(`Lineitem quantity` AS INT64) IS NULL

  UNION ALL

  SELECT
    'order_hybrid_price_cast_failures' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Hybrid Lineitem price values should cast to NUMERIC.' AS notes
  FROM order_hybrid
  WHERE `Lineitem price` IS NOT NULL
    AND SAFE_CAST(`Lineitem price` AS NUMERIC) IS NULL

  UNION ALL

  SELECT
    'order_hybrid_csv_rows_on_or_after_cutover' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'CSV rows should not appear on or after the API cutover date in the hybrid candidate.' AS notes
  FROM order_hybrid_parsed
  WHERE _hybrid_source = 'csv_history_before_cutover'
    AND DATE(created_at_ts) >= _api_cutover_date

  UNION ALL

  SELECT
    'order_hybrid_api_rows_before_cutover' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'API rows should not appear before the API cutover date in the hybrid candidate.' AS notes
  FROM order_hybrid_parsed
  WHERE _hybrid_source = 'api_forward_on_or_after_cutover'
    AND DATE(created_at_ts) < _api_cutover_date

  UNION ALL

  SELECT
    'order_hybrid_api_forward_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Rows in the order hybrid candidate sourced from API data on or after the cutover date.' AS notes
  FROM order_hybrid
  WHERE _hybrid_source = 'api_forward_on_or_after_cutover'

  UNION ALL

  SELECT
    'order_hybrid_current_raw_history_rows_preserved' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Current raw order rows before the cutover date that are present in the hybrid candidate.' AS notes
  FROM order_current_raw_parsed AS current_raw
  INNER JOIN order_hybrid_parsed AS hybrid
    ON current_raw.`Name` = hybrid.`Name`
    AND COALESCE(current_raw.`Lineitem sku`, '') = COALESCE(hybrid.`Lineitem sku`, '')
    AND COALESCE(current_raw.`Lineitem name`, '') = COALESCE(hybrid.`Lineitem name`, '')
    AND COALESCE(current_raw.`Lineitem quantity`, '') = COALESCE(hybrid.`Lineitem quantity`, '')
    AND COALESCE(current_raw.`Lineitem price`, '') = COALESCE(hybrid.`Lineitem price`, '')
    AND COALESCE(current_raw.`Created at`, '') = COALESCE(hybrid.`Created at`, '')
    AND COALESCE(LOWER(TRIM(current_raw.`Email`)), '') = COALESCE(LOWER(TRIM(hybrid.`Email`)), '')
  WHERE DATE(current_raw.created_at_ts) < hybrid._api_cutover_date

  UNION ALL

  SELECT
    'order_hybrid_orders_missing_from_current_staging' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Hybrid orders not currently present in CSV-derived staging. API-forward orders are expected here.' AS notes
  FROM order_hybrid_order_rollup AS hybrid
  LEFT JOIN order_current_staging AS current_staging
    ON hybrid.order_number = current_staging.order_number
  WHERE current_staging.order_number IS NULL

  UNION ALL

  SELECT
    'order_hybrid_current_staging_orders_missing_before_cutover' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Current staging orders before the cutover date should remain present in the hybrid candidate.' AS notes
  FROM order_current_staging AS current_staging
  CROSS JOIN (
    SELECT ANY_VALUE(_api_cutover_date) AS api_cutover_date
    FROM order_hybrid
  ) AS cutover
  LEFT JOIN order_hybrid_order_rollup AS hybrid
    ON current_staging.order_number = hybrid.order_number
  WHERE DATE(current_staging.created_at_ts) < cutover.api_cutover_date
    AND hybrid.order_number IS NULL

  UNION ALL

  SELECT
    'order_hybrid_line_item_count_differences_before_cutover' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Pre-cutover hybrid line-item counts should match current staging.' AS notes
  FROM order_hybrid_order_rollup AS hybrid
  INNER JOIN order_current_staging AS current_staging
    ON hybrid.order_number = current_staging.order_number
  WHERE DATE(current_staging.created_at_ts) < (
      SELECT ANY_VALUE(_api_cutover_date)
      FROM order_hybrid
    )
    AND COALESCE(hybrid.line_item_count, -1) != COALESCE(current_staging.line_item_count, -1)
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