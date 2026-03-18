-- Validation: marts.dim_products
-- Purpose: check grain and duplicate SKU issues

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
