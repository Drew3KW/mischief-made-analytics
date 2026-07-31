-- sql/analysis/profitability_kpi_summary.sql
-- Purpose:
-- Build monthly/channel estimated gross product profitability KPIs. 
--
-- Notes:
-- - Profit metrics are estimated gross product profit before fees.
-- - This is not net profit. 
-- - COGS coverage is surfaced explicitly so dashboard users can judge reliability. 

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_profitability_kpi_summary` AS

WITH monthly_rollup AS (
  SELECT
    order_month,
    channel,
    SUM(revenue_with_accepted_cogs) AS revenue_with_accepted_cogs,
    SUM(estimated_item_cogs) AS estimated_item_cogs,
    SUM(estimated_gross_profit_before_fees) AS estimated_gross_profit_before_fees,
    SUM(net_item_revenue_before_refunds) AS net_item_revenue_before_refunds
  FROM `mischief-made-analytics.marts.anl_product_profitability_monthly`
  GROUP BY
    order_month,
    channel
)

SELECT
  order_month,
  channel,
  ROUND(net_item_revenue_before_refunds, 2) AS net_item_revenue_before_refunds,
  ROUND(revenue_with_accepted_cogs, 2) AS revenue_with_accepted_cogs,
  ROUND(estimated_item_cogs, 2) AS estimated_item_cogs,  
  ROUND(estimated_gross_profit_before_fees, 2) AS estimated_gross_profit_before_fees,
  ROUND(
    SAFE_DIVIDE(
      estimated_gross_profit_before_fees,
      revenue_with_accepted_cogs
     ),
     4
   ) AS estimated_gross_margin_before_fees,
  ROUND(
    SAFE_DIVIDE(
      revenue_with_accepted_cogs,
      net_item_revenue_before_refunds
      ),
      4
  )  AS accepted_cogs_revenue_coverage,
  CASE
      WHEN SAFE_DIVIDE(revenue_with_accepted_cogs, net_item_revenue_before_refunds) >= 0.90 THEN 'strong_coverage'
      WHEN SAFE_DIVIDE(revenue_with_accepted_cogs, net_item_revenue_before_refunds) >= 0.70 THEN 'moderate_coverage'
      WHEN SAFE_DIVIDE(revenue_with_accepted_cogs, net_item_revenue_before_refunds) > 0 THEN 'limited_coverage'
      ELSE 'no_accepted_cogs_coverage'
  END AS profitability_coverage_status
FROM monthly_rollup;

