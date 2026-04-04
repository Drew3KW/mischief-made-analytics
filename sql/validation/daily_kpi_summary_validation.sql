-- sql/validation/daily_kpi_summary_validation.sql
-- Purpose:
-- Validation checks for marts.anl_daily_kpi_summary.

-- 1) Grain check: one row per day
SELECT
    order_date,
    COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
GROUP BY order_date
HAVING COUNT(*) > 1;

-- 2) Null date check
SELECT
    COUNT(*) AS null_order_date_rows
FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
WHERE order_date IS NULL;

-- 3) Submitted / completed / cancelled order tieout to fct_orders
WITH source_orders AS (
    SELECT
        DATE(created_at_ts) AS order_date,
        COUNT(DISTINCT order_number) AS submitted_orders,
        COUNT(DISTINCT CASE
            WHEN cancelled_at_ts IS NULL
             AND LOWER(COALESCE(financial_status, '')) NOT IN ('voided', 'cancelled')
            THEN order_number
        END) AS completed_orders,
        COUNT(DISTINCT CASE
            WHEN cancelled_at_ts IS NOT NULL
              OR LOWER(COALESCE(financial_status, '')) IN ('voided', 'cancelled')
            THEN order_number
        END) AS cancelled_orders
    FROM `mischief-made-analytics.marts.fct_orders`
    WHERE created_at_ts IS NOT NULL
      AND is_suspect_historical_timing = FALSE
    GROUP BY DATE(created_at_ts)
),
summary AS (
    SELECT
        order_date,
        submitted_orders,
        completed_orders,
        cancelled_orders
    FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
)
SELECT
    COALESCE(s.order_date, k.order_date) AS order_date,
    s.submitted_orders AS source_submitted_orders,
    k.submitted_orders AS summary_submitted_orders,
    s.completed_orders AS source_completed_orders,
    k.completed_orders AS summary_completed_orders,
    s.cancelled_orders AS source_cancelled_orders,
    k.cancelled_orders AS summary_cancelled_orders
FROM source_orders AS s
FULL OUTER JOIN summary AS k
    ON s.order_date = k.order_date
WHERE COALESCE(s.submitted_orders, 0) != COALESCE(k.submitted_orders, 0)
   OR COALESCE(s.completed_orders, 0) != COALESCE(k.completed_orders, 0)
   OR COALESCE(s.cancelled_orders, 0) != COALESCE(k.cancelled_orders, 0)
ORDER BY order_date;

-- 4) Revenue tieout to fct_orders
WITH source_revenue AS (
    SELECT
        DATE(created_at_ts) AS order_date,
        ROUND(SUM(CASE
            WHEN cancelled_at_ts IS NULL
             AND LOWER(COALESCE(financial_status, '')) NOT IN ('voided', 'cancelled')
            THEN COALESCE(order_total, 0)
            ELSE 0
        END), 2) AS gross_revenue,
        ROUND(SUM(CASE
            WHEN cancelled_at_ts IS NULL
             AND LOWER(COALESCE(financial_status, '')) NOT IN ('voided', 'cancelled')
            THEN COALESCE(refunded_amount, 0)
            ELSE 0
        END), 2) AS refunded_amount,
        ROUND(SUM(CASE
            WHEN cancelled_at_ts IS NULL
             AND LOWER(COALESCE(financial_status, '')) NOT IN ('voided', 'cancelled')
            THEN COALESCE(order_total, 0) - COALESCE(refunded_amount, 0)
            ELSE 0
        END), 2) AS net_revenue_after_refunds
    FROM `mischief-made-analytics.marts.fct_orders`
    WHERE created_at_ts IS NOT NULL
      AND is_suspect_historical_timing = FALSE
    GROUP BY DATE(created_at_ts)
),
summary AS (
    SELECT
        order_date,
        gross_revenue,
        refunded_amount,
        net_revenue_after_refunds
    FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
)
SELECT
    COALESCE(s.order_date, k.order_date) AS order_date,
    s.gross_revenue AS source_gross_revenue,
    k.gross_revenue AS summary_gross_revenue,
    s.refunded_amount AS source_refunded_amount,
    k.refunded_amount AS summary_refunded_amount,
    s.net_revenue_after_refunds AS source_net_revenue_after_refunds,
    k.net_revenue_after_refunds AS summary_net_revenue_after_refunds
FROM source_revenue AS s
FULL OUTER JOIN summary AS k
    ON s.order_date = k.order_date
WHERE COALESCE(s.gross_revenue, 0) != COALESCE(k.gross_revenue, 0)
   OR COALESCE(s.refunded_amount, 0) != COALESCE(k.refunded_amount, 0)
   OR COALESCE(s.net_revenue_after_refunds, 0) != COALESCE(k.net_revenue_after_refunds, 0)
ORDER BY order_date;

-- 5) Units tieout to fct_order_items joined to non-cancelled trusted orders
WITH source_units AS (
    SELECT
        DATE(o.created_at_ts) AS order_date,
        SUM(oi.quantity) AS units_sold,
        ROUND(SUM(oi.gross_item_revenue), 2) AS gross_item_revenue,
        ROUND(SUM(oi.net_item_revenue_before_refunds), 2) AS net_item_revenue_before_refunds
    FROM `mischief-made-analytics.marts.fct_order_items` AS oi
    INNER JOIN `mischief-made-analytics.marts.fct_orders` AS o
        ON oi.order_number = o.order_number
    WHERE o.created_at_ts IS NOT NULL
      AND o.is_suspect_historical_timing = FALSE
      AND o.cancelled_at_ts IS NULL
      AND LOWER(COALESCE(o.financial_status, '')) NOT IN ('voided', 'cancelled')
    GROUP BY DATE(o.created_at_ts)
),
summary AS (
    SELECT
        order_date,
        units_sold,
        gross_item_revenue,
        net_item_revenue_before_refunds
    FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
)
SELECT
    COALESCE(s.order_date, k.order_date) AS order_date,
    s.units_sold AS source_units_sold,
    k.units_sold AS summary_units_sold,
    s.gross_item_revenue AS source_gross_item_revenue,
    k.gross_item_revenue AS summary_gross_item_revenue,
    s.net_item_revenue_before_refunds AS source_net_item_revenue_before_refunds,
    k.net_item_revenue_before_refunds AS summary_net_item_revenue_before_refunds
FROM source_units AS s
FULL OUTER JOIN summary AS k
    ON s.order_date = k.order_date
WHERE COALESCE(s.units_sold, 0) != COALESCE(k.units_sold, 0)
   OR COALESCE(s.gross_item_revenue, 0) != COALESCE(k.gross_item_revenue, 0)
   OR COALESCE(s.net_item_revenue_before_refunds, 0) != COALESCE(k.net_item_revenue_before_refunds, 0)
ORDER BY order_date;

-- 6) New + returning customer sanity check
SELECT
    order_date,
    customers_with_completed_orders,
    new_customers,
    returning_customers,
    new_customers + returning_customers AS new_plus_returning
FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
WHERE new_customers + returning_customers != customers_with_completed_orders
ORDER BY order_date;

-- 7) Rate sanity checks
SELECT
    COUNTIF(cancellation_rate < 0 OR cancellation_rate > 1) AS invalid_cancellation_rate_rows,
    COUNTIF(refund_rate < 0 OR refund_rate > 1) AS invalid_refund_rate_rows
FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`;

-- 8) Negative metric sanity check
SELECT
    COUNTIF(submitted_orders < 0) AS negative_submitted_orders_rows,
    COUNTIF(completed_orders < 0) AS negative_completed_orders_rows,
    COUNTIF(cancelled_orders < 0) AS negative_cancelled_orders_rows,
    COUNTIF(units_sold < 0) AS negative_units_sold_rows,
    COUNTIF(gross_revenue < 0) AS negative_gross_revenue_rows,
    COUNTIF(refunded_amount < 0) AS negative_refunded_amount_rows,
    COUNTIF(net_revenue_after_refunds < 0) AS negative_net_revenue_rows
FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`;

-- 9) Full-period summary tieout
WITH summary AS (
    SELECT
        SUM(submitted_orders) AS submitted_orders,
        SUM(completed_orders) AS completed_orders,
        SUM(cancelled_orders) AS cancelled_orders,
        SUM(units_sold) AS units_sold,
        ROUND(SUM(gross_revenue), 2) AS gross_revenue,
        ROUND(SUM(refunded_amount), 2) AS refunded_amount,
        ROUND(SUM(net_revenue_after_refunds), 2) AS net_revenue_after_refunds
    FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
),
source_orders AS (
    SELECT
        COUNT(DISTINCT order_number) AS submitted_orders,
        COUNT(DISTINCT CASE
            WHEN cancelled_at_ts IS NULL
             AND LOWER(COALESCE(financial_status, '')) NOT IN ('voided', 'cancelled')
            THEN order_number
        END) AS completed_orders,
        COUNT(DISTINCT CASE
            WHEN cancelled_at_ts IS NOT NULL
              OR LOWER(COALESCE(financial_status, '')) IN ('voided', 'cancelled')
            THEN order_number
        END) AS cancelled_orders,
        ROUND(SUM(CASE
            WHEN cancelled_at_ts IS NULL
             AND LOWER(COALESCE(financial_status, '')) NOT IN ('voided', 'cancelled')
            THEN COALESCE(order_total, 0)
            ELSE 0
        END), 2) AS gross_revenue,
        ROUND(SUM(CASE
            WHEN cancelled_at_ts IS NULL
             AND LOWER(COALESCE(financial_status, '')) NOT IN ('voided', 'cancelled')
            THEN COALESCE(refunded_amount, 0)
            ELSE 0
        END), 2) AS refunded_amount,
        ROUND(SUM(CASE
            WHEN cancelled_at_ts IS NULL
             AND LOWER(COALESCE(financial_status, '')) NOT IN ('voided', 'cancelled')
            THEN COALESCE(order_total, 0) - COALESCE(refunded_amount, 0)
            ELSE 0
        END), 2) AS net_revenue_after_refunds
    FROM `mischief-made-analytics.marts.fct_orders`
    WHERE created_at_ts IS NOT NULL
      AND is_suspect_historical_timing = FALSE
),
source_units AS (
    SELECT
        SUM(oi.quantity) AS units_sold
    FROM `mischief-made-analytics.marts.fct_order_items` AS oi
    INNER JOIN `mischief-made-analytics.marts.fct_orders` AS o
        ON oi.order_number = o.order_number
    WHERE o.created_at_ts IS NOT NULL
      AND o.is_suspect_historical_timing = FALSE
      AND o.cancelled_at_ts IS NULL
      AND LOWER(COALESCE(o.financial_status, '')) NOT IN ('voided', 'cancelled')
)
SELECT
    s.submitted_orders AS summary_submitted_orders,
    so.submitted_orders AS source_submitted_orders,
    s.completed_orders AS summary_completed_orders,
    so.completed_orders AS source_completed_orders,
    s.cancelled_orders AS summary_cancelled_orders,
    so.cancelled_orders AS source_cancelled_orders,
    s.units_sold AS summary_units_sold,
    su.units_sold AS source_units_sold,
    s.gross_revenue AS summary_gross_revenue,
    so.gross_revenue AS source_gross_revenue,
    s.refunded_amount AS summary_refunded_amount,
    so.refunded_amount AS source_refunded_amount,
    s.net_revenue_after_refunds AS summary_net_revenue_after_refunds,
    so.net_revenue_after_refunds AS source_net_revenue_after_refunds
FROM summary AS s
CROSS JOIN source_orders AS so
CROSS JOIN source_units AS su;
