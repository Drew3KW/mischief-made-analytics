-- Validation: marts.dim_products
-- Purpose: check grain, duplicate SKU issues, and null title values for size variants

-- Check 1: Row count
SELECT COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.dim_products`;

-- Check 2: distinct SKU count
SELECT COUNT(DISTINCT sku) AS distinct_skus
FROM `mischief-made-analytics.marts.dim_products`;

-- Check 3: duplicate SKU detection
SELECT sku, COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.dim_products`
GROUP BY sku
HAVING COUNT(*) > 1;

-- Check 4: null title count
SELECT COUNT(*) AS null_title_rows
FROM marts.dim_products
WHERE title IS NULL;
