-- Validation: marts.fct_orders
-- Purpose: check row count vs staging, duplicate order_number detection, null email profiling, aggregate sanity checks

--1) row count should match staging
SELECT
  (SELECT COUNT(*) FROM `mischief-made-analytics.staging.stg_shopify_orders`) AS staging_rows,
  (SELECT COUNT(*) FROM `mischief-made-analytics.marts.fct_orders`) AS fact_rows;

--2) unique order key check
SELECT
  order_number,
  COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.fct_orders`
GROUP BY 1
HAVING COUNT(*) > 1;

--3) customer join coverage
SELECT
  COUNT(*) AS fact_rows,
  COUNTIF(f.customer_email IS NOT NULL AND c.customer_email IS NULL) AS unmatched_fact_rows_with_email
FROM `mischief-made-analytics.marts.fct_orders` f
LEFT JOIN `mischief-made-analytics.marts.dim_customers` c
  ON f.customer_email = c.customer_email;

--4) null email orders
SELECT
  COUNT(*) AS null_email_orders
FROM `mischief-made-analytics.marts.fct_orders`
WHERE customer_email IS NULL OR TRIM(customer_email) = '';

--5) refund profile
SELECT
  COUNT(*) AS total_orders,
  COUNTIF(refunded_amount > 0) AS refunded_orders
FROM `mischief-made-analytics.marts.fct_orders`;
