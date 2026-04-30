-- sql/validation/shopify_api_orders_landing_validation.sql
-- Purpose:
-- Validate the isolated Shopify API orders and order line items landing tables.
--
-- Notes:
-- - These checks do not modify canonical raw tables.
-- - These checks do not replace the CSV ingestion path.
-- - These checks support future API-vs-CSV order reconciliation.
-- - Current API order access may be limited to recent orders unless the Shopify app
--   has read_all_orders access.

WITH
  api_orders AS (
    SELECT
      shopify_order_graphql_id,
      SAFE_CAST(legacy_resource_id AS INT64) AS shopify_order_id,
      order_number,
      email,
      customer_email,
      created_at,
      processed_at,
      display_financial_status,
      display_fulfillment_status,
      SAFE_CAST(NULLIF(TRIM(current_subtotal_price), '') AS NUMERIC) AS current_subtotal_price,
      SAFE_CAST(NULLIF(TRIM(current_shipping_price), '') AS NUMERIC) AS current_shipping_price,
      SAFE_CAST(NULLIF(TRIM(current_total_tax), '') AS NUMERIC) AS current_total_tax,
      SAFE_CAST(NULLIF(TRIM(current_total_price), '') AS NUMERIC) AS current_total_price,
      SAFE_CAST(NULLIF(TRIM(current_total_discounts), '') AS NUMERIC) AS current_total_discounts,
      SAFE_CAST(NULLIF(TRIM(total_refunded), '') AS NUMERIC) AS total_refunded
    FROM `mischief-made-analytics.raw_load.shopify_orders_api_latest`
  ),

  api_line_items AS (
    SELECT
      shopify_line_item_graphql_id,
      shopify_order_graphql_id,
      sku,
      quantity,
      current_quantity,
      SAFE_CAST(NULLIF(TRIM(original_unit_price), '') AS NUMERIC) AS original_unit_price,
      SAFE_CAST(NULLIF(TRIM(discounted_unit_price), '') AS NUMERIC) AS discounted_unit_price,
      SAFE_CAST(NULLIF(TRIM(discounted_total), '') AS NUMERIC) AS discounted_total,
      SAFE_CAST(NULLIF(TRIM(total_discount), '') AS NUMERIC) AS total_discount
    FROM `mischief-made-analytics.raw_load.shopify_order_line_items_api_latest`
  ),

  csv_raw_orders AS (
    SELECT
      `Name` AS order_number,
      SAFE_CAST(`Id` AS INT64) AS shopify_order_id,
      `Email` AS customer_email,
      SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S %z', `Created at`) AS created_at_ts,
      `Lineitem sku` AS sku
    FROM `mischief-made-analytics.raw.shopify_orders`
  ),

  staging_orders AS (
    SELECT
      shopify_order_id,
      order_number,
      customer_email,
      created_at_ts,
      order_total,
      line_item_count
    FROM `mischief-made-analytics.staging.stg_shopify_orders`
  ),

  staging_order_items AS (
    SELECT
      shopify_order_id,
      order_number,
      sku,
      quantity,
      lineitem_price
    FROM `mischief-made-analytics.staging.stg_shopify_order_items`
  ),

  fct_orders AS (
    SELECT
      shopify_order_id,
      order_number,
      customer_email,
      created_at_ts,
      order_total,
      line_item_count
    FROM `mischief-made-analytics.marts.fct_orders`
  ),

  fct_order_items AS (
    SELECT
      shopify_order_id,
      order_number,
      sku,
      quantity,
      lineitem_price
    FROM `mischief-made-analytics.marts.fct_order_items`
  ),

  api_order_numbers AS (
    SELECT DISTINCT order_number
    FROM api_orders
    WHERE order_number IS NOT NULL
  ),

  staging_order_numbers AS (
    SELECT DISTINCT order_number
    FROM staging_orders
    WHERE order_number IS NOT NULL
  ),

  fct_order_numbers AS (
    SELECT DISTINCT order_number
    FROM fct_orders
    WHERE order_number IS NOT NULL
  ),

  checks AS (
    SELECT
      'api_order_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
      'API order landing table should not be empty.' AS notes
    FROM api_orders

    UNION ALL

    SELECT
      'api_line_item_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
      'API order line item landing table should not be empty.' AS notes
    FROM api_line_items

    UNION ALL

    SELECT
      'api_duplicate_order_graphql_ids' AS check_name,
      COUNT(*) - COUNT(DISTINCT shopify_order_graphql_id) AS result_value,
      0 AS expected_value,
      IF(
        COUNT(*) - COUNT(DISTINCT shopify_order_graphql_id) = 0,
        'PASS',
        'FAIL'
      ) AS check_status,
      'Each API order GraphQL ID should appear once.' AS notes
    FROM api_orders

    UNION ALL

    SELECT
      'api_duplicate_line_item_graphql_ids' AS check_name,
      COUNT(*) - COUNT(DISTINCT shopify_line_item_graphql_id) AS result_value,
      0 AS expected_value,
      IF(
        COUNT(*) - COUNT(DISTINCT shopify_line_item_graphql_id) = 0,
        'PASS',
        'FAIL'
      ) AS check_status,
      'Each API line item GraphQL ID should appear once.' AS notes
    FROM api_line_items

    UNION ALL

    SELECT
      'api_orders_missing_order_number' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
      'API orders should have order_number/name values.' AS notes
    FROM api_orders
    WHERE order_number IS NULL

    UNION ALL

    SELECT
      'api_line_items_missing_parent_order_id' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
      'API line items should have parent Shopify order GraphQL IDs from __parentId.' AS notes
    FROM api_line_items
    WHERE shopify_order_graphql_id IS NULL

    UNION ALL

    SELECT
      'api_line_item_orphans' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
      'Every API line item parent order ID should exist in the API order landing table.' AS notes
    FROM api_line_items AS line_items
    LEFT JOIN api_orders AS orders
      ON line_items.shopify_order_graphql_id = orders.shopify_order_graphql_id
    WHERE orders.shopify_order_graphql_id IS NULL

    UNION ALL

    SELECT
      'api_min_created_at_date' AS check_name,
      CAST(FORMAT_DATE('%Y%m%d', DATE(MIN(created_at))) AS INT64) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Earliest created_at date in API order landing table, formatted as YYYYMMDD.' AS notes
    FROM api_orders

    UNION ALL

    SELECT
      'api_max_created_at_date' AS check_name,
      CAST(FORMAT_DATE('%Y%m%d', DATE(MAX(created_at))) AS INT64) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Latest created_at date in API order landing table, formatted as YYYYMMDD.' AS notes
    FROM api_orders

    UNION ALL

    SELECT
      'raw_csv_distinct_order_numbers' AS check_name,
      COUNT(DISTINCT order_number) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Distinct order numbers in canonical CSV-derived raw orders.' AS notes
    FROM csv_raw_orders

    UNION ALL

    SELECT
      'staging_order_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Current CSV-derived staging order rows.' AS notes
    FROM staging_orders

    UNION ALL

    SELECT
      'staging_order_item_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Current CSV-derived staging order item rows.' AS notes
    FROM staging_order_items

    UNION ALL

    SELECT
      'fct_order_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Current fct_orders rows.' AS notes
    FROM fct_orders

    UNION ALL

    SELECT
      'fct_order_item_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Current fct_order_items rows.' AS notes
    FROM fct_order_items

    UNION ALL

    SELECT
      'api_order_number_overlap_with_staging' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'API order numbers found in CSV-derived staging orders.' AS notes
    FROM api_order_numbers AS api
    INNER JOIN staging_order_numbers AS staging
      USING (order_number)

    UNION ALL

    SELECT
      'api_order_number_overlap_with_fct_orders' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'API order numbers found in fct_orders.' AS notes
    FROM api_order_numbers AS api
    INNER JOIN fct_order_numbers AS fct
      USING (order_number)
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