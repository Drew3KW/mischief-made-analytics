-- File: sql/validation/shopify_canonical_raw_dry_run_validation.sql
-- Purpose:
-- Validate the Shopify API canonical raw rebuild dry run.
--
-- This validation checks whether hybrid raw candidates can safely feed
-- staging-like dry-run outputs before any production canonical raw replacement.
--
-- Important notes:
-- - This does not modify canonical raw tables.
-- - This does not modify production staging tables.
-- - This does not modify marts, analysis, or DAG behavior.
-- - REVIEW and INFO results are expected for known source/snapshot differences.

WITH cutover AS (
  SELECT
    ANY_VALUE(_api_cutover_date) AS api_cutover_date
  FROM `mischief-made-analytics.raw_load.shopify_orders_hybrid_raw_candidate`
),

schema_differences AS (
  SELECT
    'products_missing_from_dry_run' AS difference_type,
    column_name,
    data_type
  FROM (
    SELECT column_name, data_type
    FROM `mischief-made-analytics.staging.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'stg_shopify_products'

    EXCEPT DISTINCT

    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw_load.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'stg_shopify_products_hybrid_dry_run'
  )

  UNION ALL

  SELECT
    'products_extra_in_dry_run' AS difference_type,
    column_name,
    data_type
  FROM (
    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw_load.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'stg_shopify_products_hybrid_dry_run'

    EXCEPT DISTINCT

    SELECT column_name, data_type
    FROM `mischief-made-analytics.staging.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'stg_shopify_products'
  )

  UNION ALL

  SELECT
    'customers_missing_from_dry_run' AS difference_type,
    column_name,
    data_type
  FROM (
    SELECT column_name, data_type
    FROM `mischief-made-analytics.staging.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'stg_shopify_customers'

    EXCEPT DISTINCT

    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw_load.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'stg_shopify_customers_hybrid_dry_run'
  )

  UNION ALL

  SELECT
    'customers_extra_in_dry_run' AS difference_type,
    column_name,
    data_type
  FROM (
    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw_load.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'stg_shopify_customers_hybrid_dry_run'

    EXCEPT DISTINCT

    SELECT column_name, data_type
    FROM `mischief-made-analytics.staging.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'stg_shopify_customers'
  )

  UNION ALL

  SELECT
    'order_items_missing_from_dry_run' AS difference_type,
    column_name,
    data_type
  FROM (
    SELECT column_name, data_type
    FROM `mischief-made-analytics.staging.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'stg_shopify_order_items'

    EXCEPT DISTINCT

    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw_load.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'stg_shopify_order_items_hybrid_dry_run'
  )

  UNION ALL

  SELECT
    'order_items_extra_in_dry_run' AS difference_type,
    column_name,
    data_type
  FROM (
    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw_load.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'stg_shopify_order_items_hybrid_dry_run'

    EXCEPT DISTINCT

    SELECT column_name, data_type
    FROM `mischief-made-analytics.staging.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'stg_shopify_order_items'
  )

  UNION ALL

  SELECT
    'orders_missing_from_dry_run' AS difference_type,
    column_name,
    data_type
  FROM (
    SELECT column_name, data_type
    FROM `mischief-made-analytics.staging.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'stg_shopify_orders'

    EXCEPT DISTINCT

    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw_load.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'stg_shopify_orders_hybrid_dry_run'
  )

  UNION ALL

  SELECT
    'orders_extra_in_dry_run' AS difference_type,
    column_name,
    data_type
  FROM (
    SELECT column_name, data_type
    FROM `mischief-made-analytics.raw_load.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'stg_shopify_orders_hybrid_dry_run'

    EXCEPT DISTINCT

    SELECT column_name, data_type
    FROM `mischief-made-analytics.staging.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'stg_shopify_orders'
  )
),

product_current AS (
  SELECT *
  FROM `mischief-made-analytics.staging.stg_shopify_products`
),

product_dry_run AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.stg_shopify_products_hybrid_dry_run`
),

customer_current AS (
  SELECT *
  FROM `mischief-made-analytics.staging.stg_shopify_customers`
),

customer_dry_run AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.stg_shopify_customers_hybrid_dry_run`
),

order_item_current AS (
  SELECT *
  FROM `mischief-made-analytics.staging.stg_shopify_order_items`
),

order_item_dry_run AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.stg_shopify_order_items_hybrid_dry_run`
),

order_current AS (
  SELECT *
  FROM `mischief-made-analytics.staging.stg_shopify_orders`
),

order_dry_run AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.stg_shopify_orders_hybrid_dry_run`
),

order_hybrid_raw AS (
  SELECT *
  FROM `mischief-made-analytics.raw_load.shopify_orders_hybrid_raw_candidate`
),

order_item_dry_run_fingerprints AS (
  SELECT
    *,
    TO_HEX(
      MD5(
        CONCAT(
          COALESCE(TRIM(order_number), ''),
          '||',
          COALESCE(TRIM(sku), ''),
          '||',
          COALESCE(TRIM(product_name), ''),
          '||',
          COALESCE(CAST(quantity AS STRING), ''),
          '||',
          COALESCE(CAST(lineitem_price AS STRING), ''),
          '||',
          COALESCE(CAST(created_at_ts AS STRING), ''),
          '||',
          COALESCE(LOWER(TRIM(customer_email)), '')
        )
      )
    ) AS line_item_fingerprint
  FROM order_item_dry_run
),

api_forward_order_numbers AS (
  SELECT DISTINCT
    `Name` AS order_number
  FROM order_hybrid_raw
  WHERE _hybrid_source = 'api_forward_on_or_after_cutover'
),

checks AS (
  SELECT
    'schema_contract_column_differences' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Dry-run staging tables should match production staging column names and data types.' AS notes
  FROM schema_differences

  UNION ALL

  SELECT
    'product_dry_run_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
    'Product dry-run staging should not be empty.' AS notes
  FROM product_dry_run

  UNION ALL

  SELECT
    'product_dry_run_current_staging_skus_missing' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Every current production staging SKU should exist in product dry-run staging.' AS notes
  FROM (
    SELECT DISTINCT LOWER(TRIM(sku)) AS sku_key
    FROM product_current
    WHERE NULLIF(TRIM(sku), '') IS NOT NULL
  ) AS current_skus
  LEFT JOIN (
    SELECT DISTINCT LOWER(TRIM(sku)) AS sku_key
    FROM product_dry_run
    WHERE NULLIF(TRIM(sku), '') IS NOT NULL
  ) AS dry_run_skus
  USING (sku_key)
  WHERE dry_run_skus.sku_key IS NULL

  UNION ALL

  SELECT
    'product_dry_run_duplicate_nonblank_sku_keys' AS check_name,
    COUNT(*) - COUNT(DISTINCT LOWER(TRIM(sku))) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Duplicate product SKU keys are informational because catalog duplicate behavior already exists.' AS notes
  FROM product_dry_run
  WHERE NULLIF(TRIM(sku), '') IS NOT NULL

  UNION ALL

  SELECT
    'product_dry_run_price_differences_on_overlap' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
    'Product price differences on overlapping SKUs are expected review items when API rows win on overlap.' AS notes
  FROM (
    SELECT
      current_products.sku,
      current_products.price AS current_price,
      dry_run_products.price AS dry_run_price
    FROM product_current AS current_products
    INNER JOIN product_dry_run AS dry_run_products
      ON LOWER(TRIM(current_products.sku)) = LOWER(TRIM(dry_run_products.sku))
    WHERE COALESCE(current_products.price, -1) != COALESCE(dry_run_products.price, -1)
  )

  UNION ALL

  SELECT
    'customer_dry_run_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
    'Customer dry-run staging should not be empty.' AS notes
  FROM customer_dry_run

  UNION ALL

  SELECT
    'customer_dry_run_duplicate_customer_ids' AS check_name,
    COUNT(*) - COUNT(DISTINCT shopify_customer_id) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) - COUNT(DISTINCT shopify_customer_id) = 0, 'PASS', 'FAIL') AS check_status,
    'Customer dry-run staging should not contain duplicate nonnull Shopify customer IDs.' AS notes
  FROM customer_dry_run
  WHERE shopify_customer_id IS NOT NULL

  UNION ALL

  SELECT
    'customer_dry_run_current_staging_ids_missing' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Every current production staging customer ID should exist in customer dry-run staging.' AS notes
  FROM (
    SELECT DISTINCT shopify_customer_id
    FROM customer_current
    WHERE shopify_customer_id IS NOT NULL
  ) AS current_customers
  LEFT JOIN (
    SELECT DISTINCT shopify_customer_id
    FROM customer_dry_run
    WHERE shopify_customer_id IS NOT NULL
  ) AS dry_run_customers
  USING (shopify_customer_id)
  WHERE dry_run_customers.shopify_customer_id IS NULL

  UNION ALL

  SELECT
    'customer_dry_run_missing_email_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Customers missing email are allowed and should remain visible for review.' AS notes
  FROM customer_dry_run
  WHERE NULLIF(TRIM(customer_email), '') IS NULL

  UNION ALL

  SELECT
    'customer_dry_run_lifetime_metric_differences_on_overlap' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
    'Customer lifetime total/order count differences are expected review items because API data may be fresher than CSV data.' AS notes
  FROM customer_current AS current_customers
  INNER JOIN customer_dry_run AS dry_run_customers
    USING (shopify_customer_id)
  WHERE current_customers.shopify_customer_id IS NOT NULL
    AND (
      COALESCE(current_customers.total_spent, -1) != COALESCE(dry_run_customers.total_spent, -1)
      OR COALESCE(current_customers.total_orders, -1) != COALESCE(dry_run_customers.total_orders, -1)
    )

  UNION ALL

  SELECT
    'order_item_dry_run_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
    'Order item dry-run staging should not be empty.' AS notes
  FROM order_item_dry_run

  UNION ALL

  SELECT
    'order_item_dry_run_missing_order_numbers' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Every dry-run order item should have an order number.' AS notes
  FROM order_item_dry_run
  WHERE NULLIF(TRIM(order_number), '') IS NULL

  UNION ALL

  SELECT
    'order_item_dry_run_missing_created_at_ts' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Every dry-run order item should have a parsed created_at_ts.' AS notes
  FROM order_item_dry_run
  WHERE created_at_ts IS NULL

  UNION ALL

  SELECT
    'order_item_dry_run_missing_quantity' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Every dry-run order item should have a parsed quantity.' AS notes
  FROM order_item_dry_run
  WHERE quantity IS NULL

  UNION ALL

  SELECT
    'order_item_dry_run_missing_lineitem_price' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Every dry-run order item should have a parsed line item price.' AS notes
  FROM order_item_dry_run
  WHERE lineitem_price IS NULL

  UNION ALL

  SELECT
    'order_item_dry_run_duplicate_line_item_fingerprints' AS check_name,
    COUNT(*) - COUNT(DISTINCT line_item_fingerprint) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) - COUNT(DISTINCT line_item_fingerprint) = 0, 'PASS', 'FAIL') AS check_status,
    'Dry-run order item staging should not contain duplicate line-item fingerprints.' AS notes
  FROM order_item_dry_run_fingerprints

  UNION ALL

  SELECT
    'order_dry_run_rows' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
    'Order dry-run staging should not be empty.' AS notes
  FROM order_dry_run

  UNION ALL

  SELECT
    'order_dry_run_duplicate_order_numbers' AS check_name,
    COUNT(*) - COUNT(DISTINCT order_number) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) - COUNT(DISTINCT order_number) = 0, 'PASS', 'FAIL') AS check_status,
    'Dry-run order staging should remain one row per order_number.' AS notes
  FROM order_dry_run
  WHERE NULLIF(TRIM(order_number), '') IS NOT NULL

  UNION ALL

  SELECT
    'order_dry_run_api_cutover_date' AS check_name,
    CAST(NULL AS INT64) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    CONCAT('Derived API cutover date: ', CAST((SELECT api_cutover_date FROM cutover) AS STRING)) AS notes

  UNION ALL

  SELECT
    'order_dry_run_api_forward_orders_included' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Every API-forward order should appear in dry-run order staging.' AS notes
  FROM api_forward_order_numbers AS api_forward
  LEFT JOIN order_dry_run AS dry_run_orders
    USING (order_number)
  WHERE dry_run_orders.order_number IS NULL

  UNION ALL

  SELECT
    'order_dry_run_api_forward_order_count' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'API-forward orders included in dry-run order staging.' AS notes
  FROM order_dry_run AS dry_run_orders
  INNER JOIN api_forward_order_numbers AS api_forward
    USING (order_number)

  UNION ALL

  SELECT
    'order_dry_run_current_orders_missing_before_cutover' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Current production staging orders before the cutover date should remain present in dry-run staging.' AS notes
  FROM order_current AS current_orders
  CROSS JOIN cutover
  LEFT JOIN order_dry_run AS dry_run_orders
    USING (order_number)
  WHERE DATE(current_orders.created_at_ts) < cutover.api_cutover_date
    AND dry_run_orders.order_number IS NULL

  UNION ALL

  SELECT
    'order_dry_run_line_item_count_differences_before_cutover' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Pre-cutover dry-run order line item counts should match current production staging.' AS notes
  FROM order_current AS current_orders
  CROSS JOIN cutover
  INNER JOIN order_dry_run AS dry_run_orders
    USING (order_number)
  WHERE DATE(current_orders.created_at_ts) < cutover.api_cutover_date
    AND COALESCE(current_orders.line_item_count, -1) != COALESCE(dry_run_orders.line_item_count, -1)

  UNION ALL

  SELECT
    'order_dry_run_total_item_differences_before_cutover' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Pre-cutover dry-run total item counts should match current production staging.' AS notes
  FROM order_current AS current_orders
  CROSS JOIN cutover
  INNER JOIN order_dry_run AS dry_run_orders
    USING (order_number)
  WHERE DATE(current_orders.created_at_ts) < cutover.api_cutover_date
    AND COALESCE(current_orders.total_items, -1) != COALESCE(dry_run_orders.total_items, -1)

  UNION ALL

  SELECT
    'order_dry_run_order_total_differences_before_cutover' AS check_name,
    COUNT(*) AS result_value,
    0 AS expected_value,
    IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
    'Pre-cutover dry-run order totals should match current production staging.' AS notes
  FROM order_current AS current_orders
  CROSS JOIN cutover
  INNER JOIN order_dry_run AS dry_run_orders
    USING (order_number)
  WHERE DATE(current_orders.created_at_ts) < cutover.api_cutover_date
    AND ABS(COALESCE(current_orders.order_total, 0) - COALESCE(dry_run_orders.order_total, 0)) > 0.01

  UNION ALL

  SELECT
    'order_dry_run_orders_not_in_current_staging' AS check_name,
    COUNT(*) AS result_value,
    CAST(NULL AS INT64) AS expected_value,
    'INFO' AS check_status,
    'Dry-run orders not currently present in production staging. API-forward orders are expected here.' AS notes
  FROM order_dry_run AS dry_run_orders
  LEFT JOIN order_current AS current_orders
    USING (order_number)
  WHERE current_orders.order_number IS NULL
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