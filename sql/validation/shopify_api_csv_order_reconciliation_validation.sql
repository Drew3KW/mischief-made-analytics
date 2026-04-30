-- sql/validation/shopify_api_csv_order_reconciliation_validation.sql
-- Purpose:
-- Validate the Shopify API vs CSV order reconciliation view.
--
-- Notes:
-- - This is comparison-only validation.
-- - REVIEW rows are not automatic failures.
-- - API and CSV snapshots may differ because they may not represent the same
--   point in time.
-- - Current API order access may be limited to the recent-order window.

WITH
  reconciliation AS (
    SELECT *
    FROM `mischief-made-analytics.marts.anl_shopify_api_csv_order_reconciliation`
  ),

  staging_global AS (
    SELECT
      MAX(created_at_ts) AS staging_max_created_at_ts
    FROM `mischief-made-analytics.staging.stg_shopify_orders`
  ),

  status_counts AS (
    SELECT
      reconciliation_status,
      COUNT(*) AS row_count
    FROM reconciliation
    GROUP BY reconciliation_status
  ),

  order_total_status_counts AS (
    SELECT
      order_total_reconciliation_status,
      COUNT(*) AS row_count
    FROM reconciliation
    GROUP BY order_total_reconciliation_status
  ),

  line_item_count_status_counts AS (
    SELECT
      line_item_count_reconciliation_status,
      COUNT(*) AS row_count
    FROM reconciliation
    GROUP BY line_item_count_reconciliation_status
  ),

  total_items_status_counts AS (
    SELECT
      total_items_reconciliation_status,
      COUNT(*) AS row_count
    FROM reconciliation
    GROUP BY total_items_reconciliation_status
  ),

  financial_status_counts AS (
    SELECT
      financial_status_reconciliation_status,
      COUNT(*) AS row_count
    FROM reconciliation
    GROUP BY financial_status_reconciliation_status
  ),

  fulfillment_status_counts AS (
    SELECT
      fulfillment_status_reconciliation_status,
      COUNT(*) AS row_count
    FROM reconciliation
    GROUP BY fulfillment_status_reconciliation_status
  ),

  checks AS (
    SELECT
      'reconciliation_view_row_count' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
      'The reconciliation view should have rows.' AS notes
    FROM reconciliation

    UNION ALL

    SELECT
      'duplicate_unified_order_numbers' AS check_name,
      COUNT(*) - COUNT(DISTINCT unified_order_number) AS result_value,
      0 AS expected_value,
      IF(
        COUNT(*) - COUNT(DISTINCT unified_order_number) = 0,
        'PASS',
        'FAIL'
      ) AS check_status,
      'Each unified order number should appear once.' AS notes
    FROM reconciliation
    WHERE unified_order_number IS NOT NULL

    UNION ALL

    SELECT
      'api_order_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Rows from the API order landing table.' AS notes
    FROM reconciliation
    WHERE api_order_number IS NOT NULL

    UNION ALL

    SELECT
      'staging_order_rows_in_api_window' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'CSV-derived staging orders in the API-accessible date window.' AS notes
    FROM reconciliation
    WHERE staging_order_number IS NOT NULL

    UNION ALL

    SELECT
      'fct_order_rows_in_api_window' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'fct_orders rows in the API-accessible date window.' AS notes
    FROM reconciliation
    WHERE fct_order_number IS NOT NULL

    UNION ALL

    SELECT
      'matched_api_staging_fct_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'API orders matched to staging and fct_orders by order number.' AS notes
    FROM reconciliation
    WHERE reconciliation_status = 'matched_api_staging_fct'

    UNION ALL

    SELECT
      'api_only_order_rows' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
      'API orders not found in the CSV-derived staging table.' AS notes
    FROM reconciliation
    WHERE reconciliation_status = 'api_only'

    UNION ALL

    SELECT
      'api_only_orders_newer_than_staging_max_created_at' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'API-only orders created after the latest CSV-derived staging order timestamp.' AS notes
    FROM reconciliation
    CROSS JOIN staging_global
    WHERE reconciliation_status = 'api_only'
      AND api_created_at_ts > staging_global.staging_max_created_at_ts

    UNION ALL

    SELECT
      'staging_only_order_rows_in_api_window' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
      'CSV-derived staging orders in the API-accessible window not found in API landing.' AS notes
    FROM reconciliation
    WHERE reconciliation_status = 'staging_only_in_api_window'

    UNION ALL

    SELECT
      'order_total_differs_from_staging_rows' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
      'API order total differs from staging order total for matched orders.' AS notes
    FROM reconciliation
    WHERE order_total_reconciliation_status = 'order_total_differs_from_staging'

    UNION ALL

    SELECT
      'line_item_count_differs_from_staging_rows' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
      'API line item count differs from staging line item count for matched orders.' AS notes
    FROM reconciliation
    WHERE line_item_count_reconciliation_status = 'line_item_count_differs_from_staging'

    UNION ALL

    SELECT
      'total_items_differs_from_staging_rows' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
      'API total item quantity differs from staging total_items for matched orders.' AS notes
    FROM reconciliation
    WHERE total_items_reconciliation_status = 'total_items_differs_from_staging'

    UNION ALL

    SELECT
      'financial_status_differs_from_staging_rows' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
      'API financial status differs from staging financial status for matched orders.' AS notes
    FROM reconciliation
    WHERE financial_status_reconciliation_status = 'financial_status_differs_from_staging'

    UNION ALL

    SELECT
      'fulfillment_status_differs_from_staging_rows' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
      'API fulfillment status differs from staging fulfillment status for matched orders.' AS notes
    FROM reconciliation
    WHERE fulfillment_status_reconciliation_status = 'fulfillment_status_differs_from_staging'
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
  'Distribution of order reconciliation statuses.' AS notes
FROM status_counts

UNION ALL

SELECT
  CONCAT('order_total_status__', order_total_reconciliation_status) AS check_name,
  row_count AS result_value,
  CAST(NULL AS INT64) AS expected_value,
  'INFO' AS check_status,
  'Distribution of order total reconciliation statuses.' AS notes
FROM order_total_status_counts

UNION ALL

SELECT
  CONCAT('line_item_count_status__', line_item_count_reconciliation_status) AS check_name,
  row_count AS result_value,
  CAST(NULL AS INT64) AS expected_value,
  'INFO' AS check_status,
  'Distribution of line item count reconciliation statuses.' AS notes
FROM line_item_count_status_counts

UNION ALL

SELECT
  CONCAT('total_items_status__', total_items_reconciliation_status) AS check_name,
  row_count AS result_value,
  CAST(NULL AS INT64) AS expected_value,
  'INFO' AS check_status,
  'Distribution of total item quantity reconciliation statuses.' AS notes
FROM total_items_status_counts

UNION ALL

SELECT
  CONCAT('financial_status__', financial_status_reconciliation_status) AS check_name,
  row_count AS result_value,
  CAST(NULL AS INT64) AS expected_value,
  'INFO' AS check_status,
  'Distribution of financial status reconciliation statuses.' AS notes
FROM financial_status_counts

UNION ALL

SELECT
  CONCAT('fulfillment_status__', fulfillment_status_reconciliation_status) AS check_name,
  row_count AS result_value,
  CAST(NULL AS INT64) AS expected_value,
  'INFO' AS check_status,
  'Distribution of fulfillment status reconciliation statuses.' AS notes
FROM fulfillment_status_counts

ORDER BY
  CASE check_status
    WHEN 'FAIL' THEN 1
    WHEN 'REVIEW' THEN 2
    WHEN 'PASS' THEN 3
    ELSE 4
  END,
  check_name;