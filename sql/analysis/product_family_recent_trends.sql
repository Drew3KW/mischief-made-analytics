-- sql/analysis/product_family_recent_trends.sql
-- Purpose:
-- Recent trusted trend analysis for product families using trusted monthly revenue.
-- Grain: one row per product_family_key.
--
-- Notes:
-- - Compares the last 3 complete trusted months to the prior 3 complete trusted months
-- - Includes longer-term context via lifetime_months_with_sales
-- - Uses cleaned product_family_name from the trusted monthly family layer

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_product_family_recent_trends` AS

WITH max_month AS (
  SELECT
    MAX(order_month) AS latest_month
  FROM `mischief-made-analytics.marts.anl_product_revenue_monthly_by_family`
),

windowed AS (
  SELECT
    t.order_month,
    t.product_family_key,
    t.product_family_name,
    t.gross_family_revenue,
    t.units_sold,
    m.latest_month,
    DATE_SUB(m.latest_month, INTERVAL 2 MONTH) AS current_3m_start,
    m.latest_month AS current_3m_end,
    DATE_SUB(m.latest_month, INTERVAL 5 MONTH) AS prior_3m_start,
    DATE_SUB(m.latest_month, INTERVAL 3 MONTH) AS prior_3m_end
  FROM `mischief-made-analytics.marts.anl_product_revenue_monthly_by_family` AS t
  CROSS JOIN max_month AS m
),

family_rollup AS (
  SELECT
    product_family_key,
    ANY_VALUE(product_family_name) AS product_family_name,

    ROUND(SUM(
      CASE
        WHEN order_month BETWEEN current_3m_start AND current_3m_end
        THEN gross_family_revenue
        ELSE 0
      END
    ), 2) AS revenue_last_3m,

    SUM(
      CASE
        WHEN order_month BETWEEN current_3m_start AND current_3m_end
        THEN units_sold
        ELSE 0
      END
    ) AS units_last_3m,

    ROUND(SUM(
      CASE
        WHEN order_month BETWEEN prior_3m_start AND prior_3m_end
        THEN gross_family_revenue
        ELSE 0
      END
    ), 2) AS revenue_prior_3m,

    SUM(
      CASE
        WHEN order_month BETWEEN prior_3m_start AND prior_3m_end
        THEN units_sold
        ELSE 0
      END
    ) AS units_prior_3m,

    COUNTIF(
      order_month BETWEEN current_3m_start AND current_3m_end
    ) AS months_with_sales_last_3m,

    COUNTIF(
      order_month BETWEEN prior_3m_start AND prior_3m_end
    ) AS months_with_sales_prior_3m,

    COUNT(*) AS lifetime_months_with_sales,
    MIN(order_month) AS first_trusted_month_sold,
    MAX(order_month) AS most_recent_trusted_month_sold
  FROM windowed
  GROUP BY product_family_key
)

SELECT
  product_family_key,
  product_family_name,
  first_trusted_month_sold,
  most_recent_trusted_month_sold,
  lifetime_months_with_sales,
  revenue_last_3m,
  units_last_3m,
  revenue_prior_3m,
  units_prior_3m,
  months_with_sales_last_3m,
  months_with_sales_prior_3m,
  ROUND(revenue_last_3m - revenue_prior_3m, 2) AS revenue_change_3m_vs_prior_3m,
  units_last_3m - units_prior_3m AS units_change_3m_vs_prior_3m,
  CASE
    WHEN revenue_prior_3m = 0 AND revenue_last_3m > 0 THEN NULL
    ELSE ROUND(
      ((revenue_last_3m - revenue_prior_3m) / NULLIF(revenue_prior_3m, 0)) * 100,
      2
    )
  END AS revenue_pct_change_3m_vs_prior_3m,
  CASE
    WHEN units_prior_3m = 0 AND units_last_3m > 0 THEN NULL
    ELSE ROUND(
      ((units_last_3m - units_prior_3m) / NULLIF(units_prior_3m, 0)) * 100,
      2
    )
  END AS units_pct_change_3m_vs_prior_3m,
  CASE
    WHEN revenue_prior_3m = 0 AND revenue_last_3m > 0 THEN 'new_or_returning'
    WHEN revenue_last_3m = 0 AND revenue_prior_3m > 0 THEN 'inactive_recently'
    WHEN revenue_last_3m >= revenue_prior_3m * 1.25 THEN 'rising'
    WHEN revenue_last_3m <= revenue_prior_3m * 0.75 THEN 'declining'
    ELSE 'stable'
  END AS trend_status
FROM family_rollup;
