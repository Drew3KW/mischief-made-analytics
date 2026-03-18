-- Validation: marts.dim_products_historical
-- Purpose: check <main things being validated>

-- Check 1: row count, distinct product_key count
SELECT
  COUNT(*) AS row_count,
  COUNT(DISTINCT product_key) AS distinct_product_keys
FROM `mischief-made-analytics.marts.dim_products_historical`;

-- Check 2: duplicate product_key detection
SELECT
  product_key,
  COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.dim_products_historical`
GROUP BY 1
HAVING COUNT(*) > 1;

-- Check 3: source-type breakdown
SELECT
  source_type,
  COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.dim_products_historical`
GROUP BY 1
ORDER BY row_count DESC;
