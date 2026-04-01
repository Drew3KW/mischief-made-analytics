-- 1) grain check
SELECT
  COUNT(*) AS row_count,
  COUNT(DISTINCT product_family_key) AS distinct_product_families
FROM `mischief-made-analytics.marts.anl_product_family_recent_trends`;

-- 2) duplicate check
SELECT
  product_family_key,
  COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.anl_product_family_recent_trends`
GROUP BY product_family_key
HAVING COUNT(*) > 1;

-- 3) tie-out of last 3 months revenue/units to trusted monthly base
WITH max_month AS (
  SELECT MAX(order_month) AS latest_month
  FROM `mischief-made-analytics.marts.anl_product_revenue_monthly_by_family`
),
base AS (
  SELECT
    ROUND(SUM(gross_family_revenue), 2) AS expected_revenue_last_3m,
    SUM(units_sold) AS expected_units_last_3m
  FROM `mischief-made-analytics.marts.anl_product_revenue_monthly_by_family`
  CROSS JOIN max_month
  WHERE order_month BETWEEN DATE_SUB(latest_month, INTERVAL 2 MONTH) AND latest_month
),
trend AS (
  SELECT
    ROUND(SUM(revenue_last_3m), 2) AS actual_revenue_last_3m,
    SUM(units_last_3m) AS actual_units_last_3m
  FROM `mischief-made-analytics.marts.anl_product_family_recent_trends`
)
SELECT
  expected_revenue_last_3m,
  actual_revenue_last_3m,
  ROUND(expected_revenue_last_3m - actual_revenue_last_3m, 2) AS revenue_diff,
  expected_units_last_3m,
  actual_units_last_3m,
  expected_units_last_3m - actual_units_last_3m AS unit_diff
FROM base
CROSS JOIN trend;

-- 4) lifetime month sanity check for a known family
SELECT
  order_month,
  product_family_key,
  product_family_name,
  gross_family_revenue,
  units_sold
FROM `mischief-made-analytics.marts.anl_product_revenue_monthly_by_family`
WHERE product_family_key = 'ts-dag-ra'
ORDER BY order_month;

-- 5) inspect the trend output for that same family
SELECT *
FROM `mischief-made-analytics.marts.anl_product_family_recent_trends`
WHERE product_family_key = 'ts-dag-ra';

-- 6) top recent risers sanity check
SELECT *
FROM `mischief-made-analytics.marts.anl_product_family_recent_trends`
WHERE trend_status = 'rising'
ORDER BY revenue_change_3m_vs_prior_3m DESC
LIMIT 25;

-- 7) top recent decliners sanity check
SELECT *
FROM `mischief-made-analytics.marts.anl_product_family_recent_trends`
WHERE trend_status = 'declining'
ORDER BY revenue_change_3m_vs_prior_3m ASC
LIMIT 25;
