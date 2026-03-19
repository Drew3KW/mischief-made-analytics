-- sql/validation/product_family_performance_validation.sql
-- Purpose:
-- Validate the mart-layer product_key fix and the family-level analysis view.

-- ---------------------------------------------------------------------
-- 1) dim_products_historical uniqueness
-- Expected:
-- - row_count = distinct_product_keys
-- - duplicate query returns 0 rows
-- ---------------------------------------------------------------------

SELECT
  COUNT(*) AS row_count,
  COUNT(DISTINCT product_key) AS distinct_product_keys
FROM `mischief-made-analytics.marts.dim_products_historical`;

SELECT
  product_key,
  COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.dim_products_historical`
GROUP BY product_key
HAVING COUNT(*) > 1
ORDER BY row_count DESC, product_key;

-- ---------------------------------------------------------------------
-- 2) fct_order_items row-count preservation
-- Expected:
-- - staging_rows = fact_rows
-- ---------------------------------------------------------------------

SELECT
  (SELECT COUNT(*) FROM `mischief-made-analytics.staging.stg_shopify_order_items`) AS staging_rows,
  (SELECT COUNT(*) FROM `mischief-made-analytics.marts.fct_order_items`) AS fact_rows;

-- ---------------------------------------------------------------------
-- 3) fct_order_items order_item_key uniqueness
-- Expected:
-- - row_count = distinct_order_item_keys
-- - duplicate query returns 0 rows
-- ---------------------------------------------------------------------

SELECT
  COUNT(*) AS row_count,
  COUNT(DISTINCT order_item_key) AS distinct_order_item_keys
FROM `mischief-made-analytics.marts.fct_order_items`;

SELECT
  order_item_key,
  COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.fct_order_items`
GROUP BY order_item_key
HAVING COUNT(*) > 1
ORDER BY row_count DESC, order_item_key;

-- ---------------------------------------------------------------------
-- 4) Fact-to-dimension join coverage
-- Expected:
-- - unmatched_fact_rows = 0
-- ---------------------------------------------------------------------

SELECT
  COUNT(*) AS unmatched_fact_rows
FROM `mischief-made-analytics.marts.fct_order_items` AS f
LEFT JOIN `mischief-made-analytics.marts.dim_products_historical` AS d
  ON f.product_key = d.product_key
WHERE d.product_key IS NULL;

-- ---------------------------------------------------------------------
-- 5) Source-type breakdown after rebuild
-- Expected:
-- - informational only
-- - useful for understanding how much the key fix changed historical rows
-- ---------------------------------------------------------------------

SELECT
  source_type,
  COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.dim_products_historical`
GROUP BY source_type
ORDER BY source_type;

-- ---------------------------------------------------------------------
-- 6) Generic-SKU collision sanity check
-- Expected:
-- - historical generic items such as stickers should no longer collapse
--   into one fake mega-product when distinct names exist
-- ---------------------------------------------------------------------

SELECT
  product_key,
  sku,
  product_name,
  source_type
FROM `mischief-made-analytics.marts.dim_products_historical`
WHERE LOWER(TRIM(COALESCE(sku, ''))) IN (
  'sticker',
  'stickers',
  'greeting card',
  'greeting-card',
  'greeting_card',
  'card',
  'cards',
  'patch',
  'patches',
  'pin',
  'pins',
  'magnet',
  'magnets',
  'tote bag',
  'tote-bag',
  'tote_bag',
  'tote',
  'decal',
  'decal sticker'
)
   OR LOWER(TRIM(COALESCE(product_name, ''))) LIKE '%sticker%'
   OR LOWER(TRIM(COALESCE(product_name, ''))) LIKE '%greeting card%'
ORDER BY product_key, product_name;

-- ---------------------------------------------------------------------
-- 7) Family-analysis revenue tie-out
-- Expected:
-- - difference = 0
-- ---------------------------------------------------------------------

WITH fact_total AS (
  SELECT
    ROUND(SUM(quantity * lineitem_price), 2) AS expected_gross_revenue
  FROM `mischief-made-analytics.marts.fct_order_items` AS oi
  INNER JOIN `mischief-made-analytics.marts.fct_orders` AS o
    ON oi.order_number = o.order_number
  WHERE o.cancelled_at_ts IS NULL
),
family_total AS (
  SELECT
    ROUND(SUM(gross_family_revenue), 2) AS actual_gross_revenue
  FROM `mischief-made-analytics.marts.anl_product_performance_by_family`
)
SELECT
  expected_gross_revenue,
  actual_gross_revenue,
  ROUND(expected_gross_revenue - actual_gross_revenue, 2) AS difference
FROM fact_total
CROSS JOIN family_total;

-- ---------------------------------------------------------------------
-- 8) Remaining family keys that still end in size tokens
-- Expected:
-- - ideally 0 rows, or only edge cases worth manual review
-- ---------------------------------------------------------------------

SELECT
  product_family_key,
  product_family_name,
  units_sold,
  gross_family_revenue
FROM `mischief-made-analytics.marts.anl_product_performance_by_family`
WHERE REGEXP_CONTAINS(
  product_family_key,
  r'_(xx_small|x_small|small|medium|large|x_large|xx_large|xxx_large|xl|xxl|xxxl|1x|2x|3x|4x|5x|6x|1x_large|2x_large|3x_large|4x_large|5x_large|6x_large|2xl|3xl|4xl|5xl|6xl)$'
)
ORDER BY units_sold DESC, gross_family_revenue DESC;

-- ---------------------------------------------------------------------
-- 9) Top family sanity check
-- Expected:
-- - business-facing review
-- - top rows should now look believable
-- ---------------------------------------------------------------------

SELECT *
FROM `mischief-made-analytics.marts.anl_product_performance_by_family`
ORDER BY units_sold DESC
LIMIT 50;
