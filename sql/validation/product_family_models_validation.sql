-- sql/validation/product_family_models_validation.sql

-- 1) product_family_map grain check
SELECT
    product_key,
    COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.product_family_map`
GROUP BY product_key
HAVING COUNT(*) > 1;

-- 2) dim_product_families grain check
SELECT
    product_family_key,
    COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.dim_product_families`
GROUP BY product_family_key
HAVING COUNT(*) > 1;

-- 3) Every family key in the dimension should exist in the map
SELECT
    dpf.product_family_key
FROM `mischief-made-analytics.marts.dim_product_families` AS dpf
LEFT JOIN `mischief-made-analytics.marts.product_family_map` AS pfm
    ON dpf.product_family_key = pfm.product_family_key
WHERE pfm.product_family_key IS NULL;

-- 4) Product count tieout
WITH map_counts AS (
    SELECT COUNT(*) AS map_rows
    FROM `mischief-made-analytics.marts.product_family_map`
),
dim_products_hist AS (
    SELECT COUNT(*) AS hist_rows
    FROM `mischief-made-analytics.marts.dim_products_historical`
)
SELECT
    map_rows,
    hist_rows,
    map_rows - hist_rows AS diff
FROM map_counts
CROSS JOIN dim_products_hist;
