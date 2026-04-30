-- sql/validation/shopify_api_csv_customer_reconciliation_validation.sql
-- Purpose:
-- Validate the Shopify API vs CSV customer reconciliation view.
--
-- Notes:
-- - This is comparison-only validation.
-- - REVIEW rows are not automatic failures.
-- - API and CSV snapshots may differ because they may not represent the same
--   point in time.

WITH
  reconciliation AS (
    SELECT *
    FROM `mischief-made-analytics.marts.anl_shopify_api_csv_customer_reconciliation`
  ),

  status_counts AS (
    SELECT
      reconciliation_status,
      COUNT(*) AS row_count
    FROM reconciliation
    GROUP BY reconciliation_status
  ),

  email_status_counts AS (
    SELECT
      email_reconciliation_status,
      COUNT(*) AS row_count
    FROM reconciliation
    GROUP BY email_reconciliation_status
  ),

  total_orders_status_counts AS (
    SELECT
      total_orders_reconciliation_status,
      COUNT(*) AS row_count
    FROM reconciliation
    GROUP BY total_orders_reconciliation_status
  ),

  amount_spent_status_counts AS (
    SELECT
      amount_spent_reconciliation_status,
      COUNT(*) AS row_count
    FROM reconciliation
    GROUP BY amount_spent_reconciliation_status
  ),

  tax_exempt_status_counts AS (
    SELECT
      tax_exempt_reconciliation_status,
      COUNT(*) AS row_count
    FROM reconciliation
    GROUP BY tax_exempt_reconciliation_status
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
      'duplicate_unified_shopify_customer_ids' AS check_name,
      COUNT(*) - COUNT(DISTINCT unified_shopify_customer_id) AS result_value,
      0 AS expected_value,
      IF(
        COUNT(*) - COUNT(DISTINCT unified_shopify_customer_id) = 0,
        'PASS',
        'FAIL'
      ) AS check_status,
      'Each unified Shopify customer ID should appear once.' AS notes
    FROM reconciliation
    WHERE unified_shopify_customer_id IS NOT NULL

    UNION ALL

    SELECT
      'api_customer_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Rows from the API customer landing table.' AS notes
    FROM reconciliation
    WHERE api_shopify_customer_id IS NOT NULL

    UNION ALL

    SELECT
      'staging_customer_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Rows from the CSV-derived staging customer table.' AS notes
    FROM reconciliation
    WHERE staging_shopify_customer_id IS NOT NULL

    UNION ALL

    SELECT
      'dim_customer_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Rows matched to dim_customers.' AS notes
    FROM reconciliation
    WHERE dim_shopify_customer_id IS NOT NULL

    UNION ALL

    SELECT
      'matched_by_legacy_rows' AS check_name,
      COUNT(*) AS result_value,
      CAST(NULL AS INT64) AS expected_value,
      'INFO' AS check_status,
      'Rows where API legacy resource ID matched staging.shopify_customer_id.' AS notes
    FROM reconciliation
    WHERE api_shopify_customer_id IS NOT NULL
      AND staging_shopify_customer_id IS NOT NULL

    UNION ALL

    SELECT
      'api_only_customer_rows' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
      'API customers not found in the current CSV-derived staging table.' AS notes
    FROM reconciliation
    WHERE reconciliation_status = 'api_only'

    UNION ALL

    SELECT
      'staging_only_customer_rows' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
      'CSV-derived staging customers not found in the API landing table.' AS notes
    FROM reconciliation
    WHERE reconciliation_status = 'staging_only'

    UNION ALL

    SELECT
      'api_customers_missing_email' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
      'API customers without email need review because customer_email is the practical customer key.' AS notes
    FROM reconciliation
    WHERE api_shopify_customer_id IS NOT NULL
      AND api_normalized_email IS NULL

    UNION ALL

    SELECT
      'matched_legacy_email_differs_rows' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
      'API and staging matched by Shopify customer ID but have different normalized emails.' AS notes
    FROM reconciliation
    WHERE reconciliation_status = 'matched_by_legacy_email_differs'

    UNION ALL

    SELECT
      'total_orders_differs_from_staging_rows' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
      'API number_of_orders differs from staging total_orders for matched customers.' AS notes
    FROM reconciliation
    WHERE total_orders_reconciliation_status = 'total_orders_differs_from_staging'

    UNION ALL

    SELECT
      'amount_spent_differs_from_staging_rows' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
      'API amount_spent differs from staging total_spent for matched customers.' AS notes
    FROM reconciliation
    WHERE amount_spent_reconciliation_status = 'amount_spent_differs_from_staging'

    UNION ALL

    SELECT
      'tax_exempt_differs_from_staging_rows' AS check_name,
      COUNT(*) AS result_value,
      0 AS expected_value,
      IF(COUNT(*) = 0, 'PASS', 'REVIEW') AS check_status,
      'API tax_exempt differs from staging tax_exempt for matched customers.' AS notes
    FROM reconciliation
    WHERE tax_exempt_reconciliation_status = 'tax_exempt_differs_from_staging'
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
  'Distribution of customer reconciliation statuses.' AS notes
FROM status_counts

UNION ALL

SELECT
  CONCAT('email_status__', email_reconciliation_status) AS check_name,
  row_count AS result_value,
  CAST(NULL AS INT64) AS expected_value,
  'INFO' AS check_status,
  'Distribution of email reconciliation statuses.' AS notes
FROM email_status_counts

UNION ALL

SELECT
  CONCAT('total_orders_status__', total_orders_reconciliation_status) AS check_name,
  row_count AS result_value,
  CAST(NULL AS INT64) AS expected_value,
  'INFO' AS check_status,
  'Distribution of total order count reconciliation statuses.' AS notes
FROM total_orders_status_counts

UNION ALL

SELECT
  CONCAT('amount_spent_status__', amount_spent_reconciliation_status) AS check_name,
  row_count AS result_value,
  CAST(NULL AS INT64) AS expected_value,
  'INFO' AS check_status,
  'Distribution of customer spend reconciliation statuses.' AS notes
FROM amount_spent_status_counts

UNION ALL

SELECT
  CONCAT('tax_exempt_status__', tax_exempt_reconciliation_status) AS check_name,
  row_count AS result_value,
  CAST(NULL AS INT64) AS expected_value,
  'INFO' AS check_status,
  'Distribution of tax-exempt reconciliation statuses.' AS notes
FROM tax_exempt_status_counts

ORDER BY
  CASE check_status
    WHEN 'FAIL' THEN 1
    WHEN 'REVIEW' THEN 2
    WHEN 'PASS' THEN 3
    ELSE 4
  END,
  check_name;