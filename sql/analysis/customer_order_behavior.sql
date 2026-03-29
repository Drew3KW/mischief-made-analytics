-- sql/analysis/customer_order_behavior.sql
-- Purpose:
-- Customer-level order behavior view for repeat-rate, AOV, cancellation,
-- and refund analysis.
--
-- Grain:
-- One row per nonblank customer_email with at least one order.
--
-- Notes:
-- - Built from marts.fct_orders as the source of truth for order behavior
-- - customer_key currently equals normalized customer_email
-- - lifetime_orders and customer_type are based on non-cancelled orders
-- - submitted_orders is retained separately so cancellation behavior is visible

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_customer_order_behavior` AS

WITH order_base AS (
    SELECT
        customer_email,
        order_number,
        DATE(created_at_ts) AS order_date,
        created_at_ts,
        order_total,
        refunded_amount,
        cancelled_at_ts,
        financial_status,
        fulfillment_status,
        order_source,
        currency,
        shipping_country,
        shipping_province,

        CASE
            WHEN cancelled_at_ts IS NOT NULL THEN TRUE
            WHEN LOWER(financial_status) IN ('voided', 'cancelled') THEN TRUE
            ELSE FALSE
        END AS is_cancelled,

        CASE
            WHEN COALESCE(refunded_amount, 0) > 0 THEN TRUE
            ELSE FALSE
        END AS is_refunded
    FROM `mischief-made-analytics.marts.fct_orders`
    WHERE customer_email IS NOT NULL
      AND TRIM(customer_email) <> ''
),

customer_rollup AS (
    SELECT
        customer_email AS customer_key,
        customer_email,

        MIN(order_date) AS first_submitted_order_date,
        MAX(order_date) AS most_recent_submitted_order_date,

        MIN(CASE WHEN NOT is_cancelled THEN order_date END) AS first_order_date,
        MAX(CASE WHEN NOT is_cancelled THEN order_date END) AS most_recent_order_date,

        COUNT(DISTINCT order_number) AS submitted_orders,
        COUNT(DISTINCT CASE WHEN NOT is_cancelled THEN order_number END) AS lifetime_orders,
        COUNT(DISTINCT CASE WHEN is_cancelled THEN order_number END) AS cancelled_orders,
        COUNT(DISTINCT CASE WHEN is_refunded THEN order_number END) AS refunded_orders,

        ROUND(
            SUM(CASE WHEN NOT is_cancelled THEN COALESCE(order_total, 0) ELSE 0 END),
            2
        ) AS lifetime_revenue,

        ROUND(
            SUM(CASE WHEN NOT is_cancelled THEN COALESCE(refunded_amount, 0) ELSE 0 END),
            2
        ) AS lifetime_refunded_amount,

        ROUND(
            SUM(
                CASE
                    WHEN NOT is_cancelled
                        THEN COALESCE(order_total, 0) - COALESCE(refunded_amount, 0)
                    ELSE 0
                END
            ),
            2
        ) AS lifetime_net_revenue_after_refunds,

        ROUND(
            AVG(CASE WHEN NOT is_cancelled THEN order_total END),
            2
        ) AS avg_order_value,

        MIN(CASE WHEN is_refunded THEN order_date END) AS first_refund_date,
        MAX(CASE WHEN is_refunded THEN order_date END) AS most_recent_refund_date
    FROM order_base
    GROUP BY 1, 2
)

SELECT
    cr.customer_key,
    cr.customer_email,

    dc.shopify_customer_id,
    dc.first_name,
    dc.last_name,
    dc.accepts_email_marketing,
    dc.accepts_sms_marketing,
    dc.default_address_city,
    dc.default_address_province_code,
    dc.default_address_country_code,

    cr.first_order_date,
    cr.most_recent_order_date,
    cr.first_submitted_order_date,
    cr.most_recent_submitted_order_date,

    cr.submitted_orders,
    cr.lifetime_orders,
    cr.cancelled_orders,
    cr.refunded_orders,

    cr.lifetime_revenue,
    cr.lifetime_refunded_amount,
    cr.lifetime_net_revenue_after_refunds,
    cr.avg_order_value,

    CASE
        WHEN cr.lifetime_orders >= 2 THEN 'repeat'
        WHEN cr.lifetime_orders = 1 THEN 'one_time'
        ELSE 'no_completed_orders'
    END AS customer_type,

    ROUND(SAFE_DIVIDE(cr.cancelled_orders, cr.submitted_orders), 4) AS cancellation_rate,
    ROUND(SAFE_DIVIDE(cr.refunded_orders, cr.lifetime_orders), 4) AS refund_rate,

    cr.first_refund_date,
    cr.most_recent_refund_date
FROM customer_rollup cr
LEFT JOIN `mischief-made-analytics.marts.dim_customers` dc
    ON cr.customer_email = dc.customer_email;
