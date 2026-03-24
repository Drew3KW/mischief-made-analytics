--Validation queries for anl_product_revenue_monthly_by_family_trusted_dates

-- 1) grain check
SELECT
  COUNT(*) AS row_count,
  COUNT(DISTINCT CONCAT(CAST(order_month AS STRING), '||', product_family_key)) AS distinct_grain_rows
FROM `mischief-made-analytics.marts.anl_product_revenue_monthly_by_family_trusted_dates`;

-- 2) duplicate check
SELECT
  order_month,
  product_family_key,
  COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.anl_product_revenue_monthly_by_family_trusted_dates`
GROUP BY order_month, product_family_key
HAVING COUNT(*) > 1;

-- 3) tie-out to trusted subset of facts
WITH fact_monthly AS (
  SELECT
    DATE_TRUNC(DATE(o.created_at_ts), MONTH) AS order_month,
    ROUND(SUM(oi.quantity * oi.lineitem_price), 2) AS expected_gross_revenue,
    SUM(oi.quantity) AS expected_units
  FROM `mischief-made-analytics.marts.fct_order_items` AS oi
  INNER JOIN `mischief-made-analytics.marts.fct_orders` AS o
    ON oi.order_number = o.order_number
  WHERE o.cancelled_at_ts IS NULL
    AND o.is_suspect_historical_timing = FALSE
  GROUP BY order_month
),
view_monthly AS (
  SELECT
    order_month,
    ROUND(SUM(gross_family_revenue), 2) AS actual_gross_revenue,
    SUM(units_sold) AS actual_units
  FROM `mischief-made-analytics.marts.anl_product_revenue_monthly_by_family_trusted_dates`
  GROUP BY order_month
)
SELECT
  fm.order_month,
  fm.expected_gross_revenue,
  vm.actual_gross_revenue,
  ROUND(fm.expected_gross_revenue - vm.actual_gross_revenue, 2) AS revenue_difference,
  fm.expected_units,
  vm.actual_units,
  fm.expected_units - vm.actual_units AS unit_difference
FROM fact_monthly AS fm
INNER JOIN view_monthly AS vm
  ON fm.order_month = vm.order_month
ORDER BY fm.order_month;
