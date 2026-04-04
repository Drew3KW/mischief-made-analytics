-- sql/analysis/daily_kpi_summary.sql
-- Purpose:
-- Dashboard-ready daily KPI summary view for Analysis Pack v1.
--
-- Grain:
-- One row per order_date.
--
-- Notes:
-- - Uses trusted dates by default
-- - Built primarily from marts.fct_orders, with units/revenue support from marts.fct_order_items
-- - Excludes suspect historical timing rows
-- - Separates submitted vs completed vs cancelled order counts
-- - Uses customer first completed order date to identify new vs returning customers

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_daily_kpi_summary` AS

WITH order_base AS (
    SELECT
        o.order_number,
        o.customer_email,
        DATE(o.created_at_ts) AS order_date,
        o.order_total,
        o.refunded_amount,
        o.cancelled_at_ts,
        o.financial_status,
        o.is_suspect_historical_timing,
        CASE
            WHEN o.cancelled_at_ts IS NOT NULL THEN TRUE
            WHEN LOWER(COALESCE(o.financial_status, '')) IN ('voided', 'cancelled') THEN TRUE
            ELSE FALSE
        END AS is_cancelled,
        CASE
            WHEN COALESCE(o.refunded_amount, 0) > 0 THEN TRUE
            ELSE FALSE
        END AS is_refunded
    FROM `mischief-made-analytics.marts.fct_orders` AS o
    WHERE o.created_at_ts IS NOT NULL
      AND o.is_suspect_historical_timing = FALSE
),

customer_first_order AS (
    SELECT
        customer_email,
        MIN(DATE(created_at_ts)) AS first_order_date
    FROM `mischief-made-analytics.marts.fct_orders`
    WHERE customer_email IS NOT NULL
      AND TRIM(customer_email) <> ''
      AND created_at_ts IS NOT NULL
      AND is_suspect_historical_timing = FALSE
      AND cancelled_at_ts IS NULL
      AND LOWER(COALESCE(financial_status, '')) NOT IN ('voided', 'cancelled')
    GROUP BY customer_email
),

order_rollup AS (
    SELECT
        ob.order_date,
        COUNT(DISTINCT ob.order_number) AS submitted_orders,
        COUNT(DISTINCT CASE WHEN NOT ob.is_cancelled THEN ob.order_number END) AS completed_orders,
        COUNT(DISTINCT CASE WHEN ob.is_cancelled THEN ob.order_number END) AS cancelled_orders,

        ROUND(
            SUM(CASE WHEN NOT ob.is_cancelled THEN COALESCE(ob.order_total, 0) ELSE 0 END),
            2
        ) AS gross_revenue,

        ROUND(
            SUM(CASE WHEN NOT ob.is_cancelled THEN COALESCE(ob.refunded_amount, 0) ELSE 0 END),
            2
        ) AS refunded_amount,

        ROUND(
            SUM(
                CASE
                    WHEN NOT ob.is_cancelled
                        THEN COALESCE(ob.order_total, 0) - COALESCE(ob.refunded_amount, 0)
                    ELSE 0
                END
            ),
            2
        ) AS net_revenue_after_refunds,

        ROUND(
            AVG(CASE WHEN NOT ob.is_cancelled THEN ob.order_total END),
            2
        ) AS avg_order_value,

        COUNT(DISTINCT CASE
            WHEN ob.customer_email IS NOT NULL
             AND TRIM(ob.customer_email) <> ''
            THEN ob.customer_email
        END) AS customers_submitting_orders,

        COUNT(DISTINCT CASE
            WHEN NOT ob.is_cancelled
             AND ob.customer_email IS NOT NULL
             AND TRIM(ob.customer_email) <> ''
            THEN ob.customer_email
        END) AS customers_with_completed_orders,

        COUNT(DISTINCT CASE
            WHEN NOT ob.is_cancelled
             AND ob.customer_email IS NOT NULL
             AND TRIM(ob.customer_email) <> ''
             AND cfo.first_order_date = ob.order_date
            THEN ob.customer_email
        END) AS new_customers,

        COUNT(DISTINCT CASE
            WHEN NOT ob.is_cancelled
             AND ob.customer_email IS NOT NULL
             AND TRIM(ob.customer_email) <> ''
             AND cfo.first_order_date < ob.order_date
            THEN ob.customer_email
        END) AS returning_customers,

        COUNT(DISTINCT CASE
            WHEN NOT ob.is_cancelled
             AND ob.is_refunded
            THEN ob.order_number
        END) AS refunded_orders
    FROM order_base AS ob
    LEFT JOIN customer_first_order AS cfo
        ON ob.customer_email = cfo.customer_email
    GROUP BY ob.order_date
),

units_rollup AS (
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
)

SELECT
    oru.order_date,
    oru.submitted_orders,
    oru.completed_orders,
    oru.cancelled_orders,
    COALESCE(ur.units_sold, 0) AS units_sold,
    oru.customers_submitting_orders,
    oru.customers_with_completed_orders,
    oru.new_customers,
    oru.returning_customers,
    oru.gross_revenue,
    oru.refunded_amount,
    oru.net_revenue_after_refunds,
    COALESCE(ur.gross_item_revenue, 0) AS gross_item_revenue,
    COALESCE(ur.net_item_revenue_before_refunds, 0) AS net_item_revenue_before_refunds,
    oru.avg_order_value,
    ROUND(SAFE_DIVIDE(oru.cancelled_orders, oru.submitted_orders), 4) AS cancellation_rate,
    ROUND(SAFE_DIVIDE(oru.refunded_orders, oru.completed_orders), 4) AS refund_rate,
    ROUND(SAFE_DIVIDE(COALESCE(ur.units_sold, 0), oru.completed_orders), 2) AS avg_units_per_order,
    ROUND(SAFE_DIVIDE(oru.gross_revenue, oru.customers_with_completed_orders), 2) AS revenue_per_completed_customer
FROM order_rollup AS oru
LEFT JOIN units_rollup AS ur
    ON oru.order_date = ur.order_date
ORDER BY oru.order_date;
