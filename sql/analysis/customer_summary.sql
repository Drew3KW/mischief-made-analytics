-- sql/analysis/customer_summary.sql
-- Purpose:
-- Dashboard-ready monthly customer summary view for Analysis Pack v1.
--
-- Grain:
-- One row per reporting_month.
--
-- Notes:
-- - Uses trusted dates by default
-- - Built from marts.fct_orders as the source of truth for historically correct
--   month-end customer snapshots
-- - Produces both monthly activity metrics and month-end customer-base metrics
-- - Avoids using CURRENT_DATE()-based customer segment views for historical rollups

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_customer_summary` AS

WITH order_base AS (
    SELECT
        o.order_number,
        o.customer_email,
        DATE(o.created_at_ts) AS order_date,
        DATE_TRUNC(DATE(o.created_at_ts), MONTH) AS order_month,
        COALESCE(o.order_total, 0) AS order_total,
        COALESCE(o.refunded_amount, 0) AS refunded_amount,
        COALESCE(o.order_total, 0) - COALESCE(o.refunded_amount, 0) AS net_revenue_after_refunds
    FROM `mischief-made-analytics.marts.fct_orders` AS o
    WHERE o.customer_email IS NOT NULL
      AND TRIM(o.customer_email) <> ''
      AND o.created_at_ts IS NOT NULL
      AND o.is_suspect_historical_timing = FALSE
      AND o.cancelled_at_ts IS NULL
      AND LOWER(COALESCE(o.financial_status, '')) NOT IN ('voided', 'cancelled')
),

customer_first_order AS (
    SELECT
        customer_email,
        MIN(order_date) AS first_order_date,
        DATE_TRUNC(MIN(order_date), MONTH) AS first_order_month
    FROM order_base
    GROUP BY customer_email
),

month_spine AS (
    SELECT DISTINCT
        order_month AS reporting_month
    FROM order_base
),

customer_months AS (
    SELECT
        ms.reporting_month,
        cfo.customer_email,
        cfo.first_order_date,
        cfo.first_order_month
    FROM month_spine AS ms
    INNER JOIN customer_first_order AS cfo
        ON ms.reporting_month >= cfo.first_order_month
),

customer_month_snapshot AS (
    SELECT
        cm.reporting_month,
        cm.customer_email,
        cm.first_order_date,

        MAX(ob.order_date) AS most_recent_order_date_to_month,

        COUNT(DISTINCT ob.order_number) AS lifetime_orders_to_month,

        ROUND(SUM(ob.order_total), 2) AS lifetime_revenue_to_month,
        ROUND(SUM(ob.refunded_amount), 2) AS lifetime_refunded_amount_to_month,
        ROUND(SUM(ob.net_revenue_after_refunds), 2) AS lifetime_net_revenue_after_refunds_to_month,

        COUNT(DISTINCT CASE
            WHEN ob.order_month = cm.reporting_month THEN ob.order_number
        END) AS completed_orders_in_month,

        ROUND(SUM(CASE
            WHEN ob.order_month = cm.reporting_month THEN ob.order_total
            ELSE 0
        END), 2) AS gross_revenue_in_month,

        ROUND(SUM(CASE
            WHEN ob.order_month = cm.reporting_month THEN ob.refunded_amount
            ELSE 0
        END), 2) AS refunded_amount_in_month,

        ROUND(SUM(CASE
            WHEN ob.order_month = cm.reporting_month THEN ob.net_revenue_after_refunds
            ELSE 0
        END), 2) AS net_revenue_in_month

    FROM customer_months AS cm
    LEFT JOIN order_base AS ob
        ON cm.customer_email = ob.customer_email
       AND ob.order_date <= LAST_DAY(cm.reporting_month, MONTH)
    GROUP BY
        cm.reporting_month,
        cm.customer_email,
        cm.first_order_date
),

segmented_base AS (
    SELECT
        reporting_month,
        customer_email,
        first_order_date,
        most_recent_order_date_to_month,
        lifetime_orders_to_month,
        lifetime_revenue_to_month,
        lifetime_refunded_amount_to_month,
        lifetime_net_revenue_after_refunds_to_month,
        completed_orders_in_month,
        gross_revenue_in_month,
        refunded_amount_in_month,
        net_revenue_in_month,

        DATE_DIFF(
            LAST_DAY(reporting_month, MONTH),
            most_recent_order_date_to_month,
            DAY
        ) AS days_since_last_order_month_end,

        CASE
            WHEN DATE_DIFF(LAST_DAY(reporting_month, MONTH), most_recent_order_date_to_month, DAY) <= 90 THEN 'active_recent'
            WHEN DATE_DIFF(LAST_DAY(reporting_month, MONTH), most_recent_order_date_to_month, DAY) <= 180 THEN 'warm'
            WHEN DATE_DIFF(LAST_DAY(reporting_month, MONTH), most_recent_order_date_to_month, DAY) <= 365 THEN 'cooling_off'
            ELSE 'lapsed'
        END AS recency_segment,

        CASE
            WHEN lifetime_orders_to_month >= 5 THEN 'loyal'
            WHEN lifetime_orders_to_month >= 3 THEN 'repeat'
            WHEN lifetime_orders_to_month = 2 THEN 'occasional_repeat'
            WHEN lifetime_orders_to_month = 1 THEN 'one_time'
            ELSE 'other'
        END AS frequency_segment,

        CASE
            WHEN lifetime_revenue_to_month >= 500 THEN 'high_value'
            WHEN lifetime_revenue_to_month >= 150 THEN 'mid_value'
            ELSE 'low_value'
        END AS monetary_segment,

        CASE
            WHEN lifetime_orders_to_month >= 2 THEN 'repeat'
            ELSE 'one_time'
        END AS customer_type_base
    FROM customer_month_snapshot
),

segmented AS (
    SELECT
        reporting_month,
        customer_email,
        first_order_date,
        most_recent_order_date_to_month,
        lifetime_orders_to_month,
        lifetime_revenue_to_month,
        lifetime_refunded_amount_to_month,
        lifetime_net_revenue_after_refunds_to_month,
        completed_orders_in_month,
        gross_revenue_in_month,
        refunded_amount_in_month,
        net_revenue_in_month,
        days_since_last_order_month_end,
        recency_segment,
        frequency_segment,
        monetary_segment,
        customer_type_base,

        CASE
            WHEN completed_orders_in_month > 0
             AND DATE_TRUNC(first_order_date, MONTH) = reporting_month THEN TRUE
            ELSE FALSE
        END AS is_new_customer_in_month,

        CASE
            WHEN completed_orders_in_month > 0
             AND DATE_TRUNC(first_order_date, MONTH) < reporting_month THEN TRUE
            ELSE FALSE
        END AS is_returning_customer_in_month,

        CASE
            WHEN completed_orders_in_month > 0
             AND lifetime_orders_to_month >= 2 THEN TRUE
            ELSE FALSE
        END AS is_repeat_customer_in_month,

        CASE
            WHEN completed_orders_in_month > 0
             AND lifetime_orders_to_month = 1 THEN TRUE
            ELSE FALSE
        END AS is_one_time_customer_in_month,

        CASE
            WHEN completed_orders_in_month > 0
             AND lifetime_orders_to_month >= 5 THEN TRUE
            ELSE FALSE
        END AS is_loyal_customer_in_month,

        CASE
            WHEN recency_segment = 'active_recent'
             AND lifetime_orders_to_month >= 5
             AND lifetime_revenue_to_month >= 500 THEN 'loyal_high_value'
            WHEN recency_segment = 'active_recent'
             AND lifetime_orders_to_month = 1 THEN 'recent_one_time'
            WHEN recency_segment = 'lapsed'
             AND lifetime_revenue_to_month >= 500 THEN 'lapsed_high_value'
            ELSE 'other'
        END AS flagship_rfm_segment
    FROM segmented_base
),

monthly_rollup AS (
    SELECT
        reporting_month,

        COUNT(*) AS total_customers,
        COUNTIF(completed_orders_in_month > 0) AS customers_with_completed_orders,

        COUNTIF(is_new_customer_in_month) AS new_customers,
        COUNTIF(is_returning_customer_in_month) AS returning_customers,

        COUNTIF(customer_type_base = 'one_time') AS one_time_customers,
        COUNTIF(customer_type_base = 'repeat') AS repeat_customers,
        COUNTIF(lifetime_orders_to_month >= 5) AS loyal_customers,

        COUNTIF(recency_segment = 'active_recent') AS active_recent_customers,
        COUNTIF(recency_segment = 'warm') AS warm_customers,
        COUNTIF(recency_segment = 'cooling_off') AS cooling_off_customers,
        COUNTIF(recency_segment = 'lapsed') AS lapsed_customers,

        COUNTIF(monetary_segment = 'high_value') AS high_value_customers,
        COUNTIF(monetary_segment = 'mid_value') AS mid_value_customers,
        COUNTIF(monetary_segment = 'low_value') AS low_value_customers,

        COUNTIF(flagship_rfm_segment = 'loyal_high_value') AS loyal_high_value_customers,
        COUNTIF(flagship_rfm_segment = 'recent_one_time') AS recent_one_time_customers,
        COUNTIF(flagship_rfm_segment = 'lapsed_high_value') AS lapsed_high_value_customers,

        ROUND(SUM(gross_revenue_in_month), 2) AS gross_revenue_in_month,
        ROUND(SUM(refunded_amount_in_month), 2) AS refunded_amount_in_month,
        ROUND(SUM(net_revenue_in_month), 2) AS net_revenue_in_month,

        ROUND(SUM(CASE
            WHEN is_new_customer_in_month THEN net_revenue_in_month
            ELSE 0
        END), 2) AS new_customer_net_revenue_in_month,

        ROUND(SUM(CASE
            WHEN is_returning_customer_in_month THEN net_revenue_in_month
            ELSE 0
        END), 2) AS returning_customer_net_revenue_in_month,

        ROUND(AVG(lifetime_net_revenue_after_refunds_to_month), 2) AS avg_lifetime_value_customer_base,
        ROUND(AVG(lifetime_orders_to_month), 2) AS avg_completed_orders_per_customer_base,

        ROUND(
            SAFE_DIVIDE(SUM(completed_orders_in_month), COUNTIF(completed_orders_in_month > 0)),
            2
        ) AS avg_completed_orders_per_active_customer,

        ROUND(
            SAFE_DIVIDE(SUM(net_revenue_in_month), COUNTIF(completed_orders_in_month > 0)),
            2
        ) AS revenue_per_active_customer,

        ROUND(
            SAFE_DIVIDE(COUNTIF(is_new_customer_in_month), COUNTIF(completed_orders_in_month > 0)),
            4
        ) AS pct_new_customers,

        ROUND(
            SAFE_DIVIDE(COUNTIF(is_returning_customer_in_month), COUNTIF(completed_orders_in_month > 0)),
            4
        ) AS pct_returning_customers,

        ROUND(
            SAFE_DIVIDE(COUNTIF(customer_type_base = 'repeat'), COUNT(*)),
            4
        ) AS repeat_customer_rate,

        ROUND(
            SAFE_DIVIDE(COUNTIF(lifetime_orders_to_month >= 5), COUNT(*)),
            4
        ) AS loyal_customer_rate,

        ROUND(
            SAFE_DIVIDE(COUNTIF(completed_orders_in_month > 0), COUNT(*)),
            4
        ) AS active_customer_rate

    FROM segmented
    GROUP BY reporting_month
),

final AS (
    SELECT
        reporting_month,
        total_customers,
        customers_with_completed_orders,
        new_customers,
        returning_customers,
        one_time_customers,
        repeat_customers,
        loyal_customers,
        active_recent_customers,
        warm_customers,
        cooling_off_customers,
        lapsed_customers,
        high_value_customers,
        mid_value_customers,
        low_value_customers,
        loyal_high_value_customers,
        recent_one_time_customers,
        lapsed_high_value_customers,
        gross_revenue_in_month,
        refunded_amount_in_month,
        net_revenue_in_month,
        new_customer_net_revenue_in_month,
        returning_customer_net_revenue_in_month,
        avg_lifetime_value_customer_base,
        avg_completed_orders_per_customer_base,
        avg_completed_orders_per_active_customer,
        revenue_per_active_customer,
        pct_new_customers,
        pct_returning_customers,
        repeat_customer_rate,
        loyal_customer_rate,
        active_customer_rate,

        LAG(total_customers) OVER (ORDER BY reporting_month) AS prior_month_total_customers,
        total_customers - LAG(total_customers) OVER (ORDER BY reporting_month) AS total_customers_mom_change,
        ROUND(
            SAFE_DIVIDE(
                total_customers - LAG(total_customers) OVER (ORDER BY reporting_month),
                LAG(total_customers) OVER (ORDER BY reporting_month)
            ),
            4
        ) AS total_customers_mom_pct_change,

        LAG(customers_with_completed_orders) OVER (ORDER BY reporting_month) AS prior_month_active_customers,
        customers_with_completed_orders - LAG(customers_with_completed_orders) OVER (ORDER BY reporting_month) AS active_customers_mom_change,
        ROUND(
            SAFE_DIVIDE(
                customers_with_completed_orders - LAG(customers_with_completed_orders) OVER (ORDER BY reporting_month),
                LAG(customers_with_completed_orders) OVER (ORDER BY reporting_month)
            ),
            4
        ) AS active_customers_mom_pct_change,

        LAG(net_revenue_in_month) OVER (ORDER BY reporting_month) AS prior_month_net_revenue_in_month,
        net_revenue_in_month - LAG(net_revenue_in_month) OVER (ORDER BY reporting_month) AS net_revenue_mom_change,
        ROUND(
            SAFE_DIVIDE(
                net_revenue_in_month - LAG(net_revenue_in_month) OVER (ORDER BY reporting_month),
                LAG(net_revenue_in_month) OVER (ORDER BY reporting_month)
            ),
            4
        ) AS net_revenue_mom_pct_change
    FROM monthly_rollup
)

SELECT
    reporting_month,
    total_customers,
    customers_with_completed_orders,
    new_customers,
    returning_customers,
    one_time_customers,
    repeat_customers,
    loyal_customers,
    active_recent_customers,
    warm_customers,
    cooling_off_customers,
    lapsed_customers,
    high_value_customers,
    mid_value_customers,
    low_value_customers,
    loyal_high_value_customers,
    recent_one_time_customers,
    lapsed_high_value_customers,
    gross_revenue_in_month,
    refunded_amount_in_month,
    net_revenue_in_month,
    new_customer_net_revenue_in_month,
    returning_customer_net_revenue_in_month,
    avg_lifetime_value_customer_base,
    avg_completed_orders_per_customer_base,
    avg_completed_orders_per_active_customer,
    revenue_per_active_customer,
    pct_new_customers,
    pct_returning_customers,
    repeat_customer_rate,
    loyal_customer_rate,
    active_customer_rate,
    prior_month_total_customers,
    total_customers_mom_change,
    total_customers_mom_pct_change,
    prior_month_active_customers,
    active_customers_mom_change,
    active_customers_mom_pct_change,
    prior_month_net_revenue_in_month,
    net_revenue_mom_change,
    net_revenue_mom_pct_change
FROM final
ORDER BY reporting_month;
