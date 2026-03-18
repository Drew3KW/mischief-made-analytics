-- Validation: marts.dim_customers
-- Purpose: check row count, distinct email count, duplicate email detection, unmatched fact-to-dim check using non-null emails

-- Check 1: row & distinct email counts
SELECT
  COUNT(*) AS row_count,
  COUNT(DISTINCT customer_email) AS distinct_emails
FROM `mischief-made-analytics.marts.dim_customers`;

-- Check 2: duplicate email detection
SELECT
  customer_email,
  COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.dim_customers`
GROUP BY 1
HAVING COUNT(*) > 1;

-- Check 3: unmatched fact-to-dim check using non-null emails
SELECT
  COUNT(*) AS total_orders,
  COUNTIF(o.customer_email IS NOT NULL AND c.customer_email IS NULL) AS unmatched_orders_with_email
FROM `mischief-made-analytics.staging.stg_shopify_orders` o
LEFT JOIN `mischief-made-analytics.marts.dim_customers` c
  ON LOWER(TRIM(o.customer_email)) = c.customer_email;
