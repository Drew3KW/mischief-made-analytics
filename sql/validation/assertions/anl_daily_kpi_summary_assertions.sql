ASSERT (
  (
    SELECT COUNT(*)
    FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
    WHERE order_date IS NULL
  ) = 0
) AS 'anl_daily_kpi_summary has null order_date values';

ASSERT (
  (
    SELECT COUNT(*)
    FROM (
      SELECT order_date
      FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
      GROUP BY 1
      HAVING COUNT(*) > 1
    )
  ) = 0
) AS 'anl_daily_kpi_summary has duplicate order_date rows';

ASSERT (
  (
    SELECT COUNT(*)
    FROM (
      SELECT
        d.order_date
      FROM `mischief-made-analytics.marts.anl_daily_kpi_summary` d
      JOIN (
        SELECT
          DATE(created_at_ts) AS order_date,
          COUNT(DISTINCT order_number) AS expected_completed_orders
        FROM `mischief-made-analytics.marts.fct_orders`
        WHERE created_at_ts IS NOT NULL
          AND is_suspect_historical_timing = FALSE
          AND NOT (
            cancelled_at_ts IS NOT NULL
            OR LOWER(COALESCE(financial_status, '')) IN ('voided', 'cancelled')
          )
        GROUP BY 1
      ) f
        ON d.order_date = f.order_date
      WHERE d.completed_orders != f.expected_completed_orders
    )
  ) = 0
) AS 'anl_daily_kpi_summary completed_orders does not tie out to fct_orders';

ASSERT (
  (
    SELECT COUNT(*)
    FROM (
      SELECT
        d.order_date
      FROM `mischief-made-analytics.marts.anl_daily_kpi_summary` d
      JOIN (
        SELECT
          DATE(created_at_ts) AS order_date,
          ROUND(SUM(order_total), 2) AS expected_revenue
        FROM `mischief-made-analytics.marts.fct_orders`
        WHERE created_at_ts IS NOT NULL
          AND is_suspect_historical_timing = FALSE
          AND NOT (
            cancelled_at_ts IS NOT NULL
            OR LOWER(COALESCE(financial_status, '')) IN ('voided', 'cancelled')
          )
        GROUP BY 1
      ) f
        ON d.order_date = f.order_date
      WHERE ROUND(d.gross_revenue, 2) != f.expected_revenue
    )
  ) = 0
) AS 'anl_daily_kpi_summary gross_revenue does not tie out to fct_orders';
