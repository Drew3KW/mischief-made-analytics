-- File: sql/validation/shopify_api_shadow_staging_comparison.sql
-- Purpose:
-- Compare Shopify API shadow staging tables against current CSV-derived
-- staging tables.
--
-- Important notes:
-- - These checks do not modify canonical raw tables.
-- - These checks do not modify production staging tables.
-- - REVIEW results are expected where API and CSV exports legitimately differ.

WITH product_shadow AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.stg_shopify_products_api_shadow`
),

product_current AS (
  SELECT *
  FROM `mischief-made-analytics.staging.stg_shopify_products`
),

product_shadow_by_sku AS (
  SELECT
    LOWER(TRIM(sku)) AS sku_key,
    ANY_VALUE(sku) AS sku,
    ANY_VALUE(title) AS title,
    MAX(price) AS price,
    MAX(compare_at_price) AS compare_at_price,
    MAX(inventory_quantity) AS inventory_quantity,
    ANY_VALUE(status) AS status
  FROM product_shadow
  WHERE NULLIF(TRIM(sku), '') IS NOT NULL
  GROUP BY sku_key
),

product_current_by_sku AS (
  SELECT
    LOWER(TRIM(sku)) AS sku_key,
    ANY_VALUE(sku) AS sku,
    ANY_VALUE(title) AS title,
    MAX(price) AS price,
    MAX(compare_at_price) AS compare_at_price,
    MAX(inventory_quantity) AS inventory_quantity,
    ANY_VALUE(status) AS status
  FROM product_current
  WHERE NULLIF(TRIM(sku), '') IS NOT NULL
  GROUP BY sku_key
),

customer_shadow AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.stg_shopify_customers_api_shadow`
),

customer_current AS (
  SELECT *
  FROM `mischief-made-analytics.staging.stg_shopify_customers`
),

customer_shadow_by_id AS (
  SELECT *
  FROM customer_shadow
  WHERE shopify_customer_id IS NOT NULL
),

customer_current_by_id AS (
  SELECT *
  FROM customer_current
  WHERE shopify_customer_id IS NOT NULL
),

order_item_shadow AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.stg_shopify_order_items_api_shadow`
),

order_item_current AS (
  SELECT *
  FROM `mischief-made-analytics.staging.stg_shopify_order_items`
),

order_shadow AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.stg_shopify_orders_api_shadow`
),

order_current AS (
  SELECT *
  FROM `mischief-made-analytics.staging.stg_shopify_orders`
),

checks AS (
  SELECT
    'product_shadow_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
    'Product shadow staging should not be empty.' AS notes
  FROM product_shadow

  UNION ALL

  SELECT
    'product_shadow_blank_skus' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Product shadow staging should filter blank SKUs like current staging.' AS notes
  FROM product_shadow
  WHERE NULLIF(TRIM(sku), '') IS NULL

  UNION ALL

  SELECT
    'product_shadow_duplicate_sku_keys' AS check_name,
    COUNT(*) - COUNT(DISTINCT LOWER(TRIM(sku))) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Duplicate product SKU keys are informational because catalog duplicate behavior already exists upstream.' AS notes
  FROM product_shadow
  WHERE NULLIF(TRIM(sku), '') IS NOT NULL

  UNION ALL

  SELECT
    'product_shadow_skus_missing_from_current_staging' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
    'API shadow product SKUs that do not currently appear in CSV-derived staging.' AS notes
  FROM product_shadow_by_sku AS shadow
  LEFT JOIN product_current_by_sku AS current
    USING (sku_key)
  WHERE current.sku_key IS NULL

  UNION ALL

  SELECT
    'product_price_differences_on_overlap' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
    'Overlapping product SKUs where API shadow price differs from current staging price.' AS notes
  FROM product_shadow_by_sku AS shadow
  INNER JOIN product_current_by_sku AS current
    USING (sku_key)
  WHERE COALESCE(shadow.price, -999999999) != COALESCE(current.price, -999999999)

  UNION ALL

  SELECT
    'product_compare_at_price_differences_on_overlap' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
    'Overlapping product SKUs where API shadow compare-at price differs from current staging.' AS notes
  FROM product_shadow_by_sku AS shadow
  INNER JOIN product_current_by_sku AS current
    USING (sku_key)
  WHERE COALESCE(shadow.compare_at_price, -999999999) != COALESCE(current.compare_at_price, -999999999)

  UNION ALL

  SELECT
    'customer_shadow_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
    'Customer shadow staging should not be empty.' AS notes
  FROM customer_shadow

  UNION ALL

  SELECT
    'customer_shadow_duplicate_customer_ids' AS check_name,
    COUNT(*) - COUNT(DISTINCT shopify_customer_id) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) - COUNT(DISTINCT shopify_customer_id) = 0, 'PASS', 'FAIL') AS check_status,
    'Customer shadow staging should not have duplicate nonnull customer IDs.' AS notes
  FROM customer_shadow
  WHERE shopify_customer_id IS NOT NULL

  UNION ALL

  SELECT
    'customer_shadow_missing_emails' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Customers missing email are allowed and should be reviewed as source coverage.' AS notes
  FROM customer_shadow
  WHERE NULLIF(TRIM(customer_email), '') IS NULL

  UNION ALL

  SELECT
    'customer_shadow_ids_missing_from_current_staging' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'API shadow customers that do not currently appear in CSV-derived staging.' AS notes
  FROM customer_shadow_by_id AS shadow
  LEFT JOIN customer_current_by_id AS current
    ON shadow.shopify_customer_id = current.shopify_customer_id
  WHERE current.shopify_customer_id IS NULL

  UNION ALL

  SELECT
    'customer_current_ids_missing_from_shadow' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'CSV-derived staging customers that do not currently appear in API shadow staging.' AS notes
  FROM customer_current_by_id AS current
  LEFT JOIN customer_shadow_by_id AS shadow
    ON current.shopify_customer_id = shadow.shopify_customer_id
  WHERE shadow.shopify_customer_id IS NULL

  UNION ALL

  SELECT
    'customer_total_spent_differences_on_overlap' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
    'Overlapping customers where API shadow total_spent differs from current staging.' AS notes
  FROM customer_shadow_by_id AS shadow
  INNER JOIN customer_current_by_id AS current
    ON shadow.shopify_customer_id = current.shopify_customer_id
  WHERE ABS(COALESCE(shadow.total_spent, 0) - COALESCE(current.total_spent, 0)) > 0.01

  UNION ALL

  SELECT
    'customer_total_orders_differences_on_overlap' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
    'Overlapping customers where API shadow total_orders differs from current staging.' AS notes
  FROM customer_shadow_by_id AS shadow
  INNER JOIN customer_current_by_id AS current
    ON shadow.shopify_customer_id = current.shopify_customer_id
  WHERE COALESCE(shadow.total_orders, -1) != COALESCE(current.total_orders, -1)

  UNION ALL

  SELECT
    'customer_tax_exempt_differences_on_overlap' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
    'Overlapping customers where normalized API shadow tax_exempt differs from current staging.' AS notes
  FROM customer_shadow_by_id AS shadow
  INNER JOIN customer_current_by_id AS current
    ON shadow.shopify_customer_id = current.shopify_customer_id
  WHERE LOWER(TRIM(COALESCE(shadow.tax_exempt, ''))) != LOWER(TRIM(COALESCE(current.tax_exempt, '')))

  UNION ALL

  SELECT
    'order_item_shadow_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
    'Order-item shadow staging should not be empty.' AS notes
  FROM order_item_shadow

  UNION ALL

  SELECT
    'order_item_shadow_missing_order_numbers' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Every shadow order item should have an order number.' AS notes
  FROM order_item_shadow
  WHERE order_number IS NULL

  UNION ALL

  SELECT
    'order_item_shadow_missing_created_at' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
    'Every shadow order item should have a parsed created_at timestamp.' AS notes
  FROM order_item_shadow
  WHERE created_at_ts IS NULL

  UNION ALL

  SELECT
    'order_shadow_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
    'Order shadow staging should not be empty.' AS notes
  FROM order_shadow

  UNION ALL

  SELECT
    'order_shadow_duplicate_order_numbers' AS check_name,
    COUNT(*) - COUNT(DISTINCT order_number) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) - COUNT(DISTINCT order_number) = 0, 'PASS', 'FAIL') AS check_status,
    'Order shadow staging should be one row per order number.' AS notes
  FROM order_shadow
  WHERE order_number IS NOT NULL

  UNION ALL

  SELECT
    'order_shadow_orders_missing_from_current_staging' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'API shadow orders that do not currently appear in CSV-derived staging. Newer API-only orders are expected.' AS notes
  FROM order_shadow AS shadow
  LEFT JOIN order_current AS current
    ON shadow.order_number = current.order_number
  WHERE current.order_number IS NULL

  UNION ALL

  SELECT
    'order_current_orders_missing_from_shadow' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'CSV-derived staging orders that do not appear in API shadow staging. Historical CSV-only orders are expected.' AS notes
  FROM order_current AS current
  LEFT JOIN order_shadow AS shadow
    ON current.order_number = shadow.order_number
  WHERE shadow.order_number IS NULL

  UNION ALL

  SELECT
    'order_total_differences_on_overlap' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
    'Overlapping orders where API shadow order_total differs from current staging.' AS notes
  FROM order_shadow AS shadow
  INNER JOIN order_current AS current
    ON shadow.order_number = current.order_number
  WHERE ABS(COALESCE(shadow.order_total, 0) - COALESCE(current.order_total, 0)) > 0.01

  UNION ALL

  SELECT
    'order_line_item_count_differences_on_overlap' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
    'Overlapping orders where API shadow line_item_count differs from current staging.' AS notes
  FROM order_shadow AS shadow
  INNER JOIN order_current AS current
    ON shadow.order_number = current.order_number
  WHERE COALESCE(shadow.line_item_count, -1) != COALESCE(current.line_item_count, -1)

  UNION ALL

  SELECT
    'order_total_items_differences_on_overlap' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
    'Overlapping orders where API shadow total_items differs from current staging.' AS notes
  FROM order_shadow AS shadow
  INNER JOIN order_current AS current
    ON shadow.order_number = current.order_number
  WHERE COALESCE(shadow.total_items, -1) != COALESCE(current.total_items, -1)

  UNION ALL

  SELECT
    'order_financial_status_differences_on_overlap' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
    'Overlapping orders where API shadow financial_status differs from current staging.' AS notes
  FROM order_shadow AS shadow
  INNER JOIN order_current AS current
    ON shadow.order_number = current.order_number
  WHERE LOWER(TRIM(COALESCE(shadow.financial_status, ''))) != LOWER(TRIM(COALESCE(current.financial_status, '')))

  UNION ALL

  SELECT
    'order_fulfillment_status_differences_on_overlap' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Fulfillment status differences are informational because API and CSV status timing can differ.' AS notes
  FROM order_shadow AS shadow
  INNER JOIN order_current AS current
    ON shadow.order_number = current.order_number
  WHERE LOWER(TRIM(COALESCE(shadow.fulfillment_status, ''))) != LOWER(TRIM(COALESCE(current.fulfillment_status, '')))
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