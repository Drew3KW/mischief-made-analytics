-- sql/validation/product_revenue_monthly_by_family_trusted_dates_validation.sql

-- 1) grain check
SELECT
  COUNT(*) AS row_count,
  COUNT(DISTINCT CONCAT(CAST(order_month AS STRING), '||', product_family_key)) AS distinct_family_month_rows
FROM `mischief-made-analytics.marts.anl_product_revenue_monthly_by_family_trusted_dates`;

-- 2) duplicate check
SELECT
  order_month,
  product_family_key,
  COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.anl_product_revenue_monthly_by_family_trusted_dates`
GROUP BY
  order_month,
  product_family_key
HAVING COUNT(*) > 1
ORDER BY row_count DESC, order_month, product_family_key;

-- 3) spot-check cleaned names for previously problematic families
SELECT
  order_month,
  product_family_key,
  product_family_name,
  units_sold,
  gross_family_revenue
FROM `mischief-made-analytics.marts.anl_product_revenue_monthly_by_family_trusted_dates`
WHERE product_family_key IN ('ts-dag-ra', 'ts-lad-ra', 'ts-tw-ri', 'ts-bor-rag')
ORDER BY product_family_key, order_month;

-- 4) rollup totals
SELECT
  ROUND(SUM(gross_family_revenue), 2) AS total_revenue,
  SUM(units_sold) AS total_units
FROM `mischief-made-analytics.marts.anl_product_revenue_monthly_by_family_trusted_dates`;
