-- Validation: marts.fct_order_items
-- Purpose: check staging and fact row counts, duplicate order_item_key detection, join coverage to dim_products_historical, join coverage to dim_customers

-- Check 1: staging and fact row counts
SELECT
  (SELECT COUNT(*) FROM `mischief-made-analytics.staging.stg_shopify_order_items`) AS staging_rows,
  (SELECT COUNT(*) FROM `mischief-made-analytics.marts.fct_order_items`) AS fact_rows;

-- Check 2: duplicate order_item_key detection
SELECT
  order_item_key,
  COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.fct_order_items`
GROUP BY 1
HAVING COUNT(*) > 1;

-- Check 3: join coverage to dim_products_historical
SELECT
  COUNT(*) AS fact_rows,
  COUNTIF(p.product_key IS NULL) AS unmatched_fact_rows
FROM `mischief-made-analytics.marts.fct_order_items` f
LEFT JOIN `mischief-made-analytics.marts.dim_products_historical` p
  ON f.product_key = p.product_key;

-- Check 4: join coverage to dim_customers
SELECT
  COUNT(*) AS fact_rows,
  COUNTIF(f.customer_email IS NOT NULL AND c.customer_email IS NULL) AS unmatched_fact_rows_with_email
FROM `mischief-made-analytics.marts.fct_order_items` f
LEFT JOIN `mischief-made-analytics.marts.dim_customers` c
  ON f.customer_email = c.customer_email;
