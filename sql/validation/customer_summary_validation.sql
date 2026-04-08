-- sql/validation/customer_summary_validation.sql
-- Purpose:
-- Validation checks for marts.anl_customer_summary.

-- 1) Grain check: one row per month
SELECT
    reporting_month,
    COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.anl_customer_summary`
GROUP BY reporting_month
HAVING COUNT(*) > 1;


-- 2) Null month check
SELECT
    COUNT(*) AS null_reporting_month_rows
FROM `mischief-made-analytics.marts.anl_customer_summary`
WHERE reporting_month IS NULL;


-- 3) Revenue tieout to monthly business summary
-- Note:
-- Do not use anl_monthly_business_summary to validate monthly distinct
-- customer counts, because its customer metrics are rolled up from daily summaries.
SELECT
    COALESCE(cs.reporting_month, mbs.order_month) AS reporting_month,
    cs.net_revenue_in_month AS customer_summary_net_revenue,
    mbs.net_revenue_after_refunds AS monthly_business_net_revenue,
    ROUND(
        COALESCE(cs.net_revenue_in_month, 0) - COALESCE(mbs.net_revenue_after_refunds, 0),
        2
    ) AS revenue_diff
FROM `mischief-made-analytics.marts.anl_customer_summary` AS cs
FULL OUTER JOIN `mischief-made-analytics.marts.anl_monthly_business_summary` AS mbs
    ON cs.reporting_month = mbs.order_month
WHERE ROUND(COALESCE(cs.net_revenue_in_month, 0), 2)
   != ROUND(COALESCE(mbs.net_revenue_after_refunds, 0), 2)
ORDER BY reporting_month;


-- 4) Monthly distinct customer tieout from source orders
-- Purpose:
-- Validate customer_summary monthly distinct customer counts directly
-- from fct_orders using trusted completed-order logic.
WITH order_base AS (
    SELECT
        customer_email,
        DATE(created_at_ts) AS order_date,
        DATE_TRUNC(DATE(created_at_ts), MONTH) AS reporting_month
    FROM `mischief-made-analytics.marts.fct_orders`
    WHERE customer_email IS NOT NULL
      AND TRIM(customer_email) <> ''
      AND created_at_ts IS NOT NULL
      AND is_suspect_historical_timing = FALSE
      AND cancelled_at_ts IS NULL
      AND LOWER(COALESCE(financial_status, '')) NOT IN ('voided', 'cancelled')
),

customer_first_order AS (
    SELECT
        customer_email,
        MIN(order_date) AS first_order_date,
        DATE_TRUNC(MIN(order_date), MONTH) AS first_order_month
    FROM order_base
    GROUP BY customer_email
),

monthly_distincts AS (
    SELECT
        ob.reporting_month,
        COUNT(DISTINCT ob.customer_email) AS customers_with_completed_orders,
        COUNT(DISTINCT CASE
            WHEN cfo.first_order_month = ob.reporting_month THEN ob.customer_email
        END) AS new_customers,
        COUNT(DISTINCT CASE
            WHEN cfo.first_order_month < ob.reporting_month THEN ob.customer_email
        END) AS returning_customers
    FROM order_base AS ob
    INNER JOIN customer_first_order AS cfo
        ON ob.customer_email = cfo.customer_email
    GROUP BY ob.reporting_month
)

SELECT
    COALESCE(cs.reporting_month, md.reporting_month) AS reporting_month,
    cs.customers_with_completed_orders AS summary_active_customers,
    md.customers_with_completed_orders AS source_active_customers,
    cs.new_customers AS summary_new_customers,
    md.new_customers AS source_new_customers,
    cs.returning_customers AS summary_returning_customers,
    md.returning_customers AS source_returning_customers
FROM `mischief-made-analytics.marts.anl_customer_summary` AS cs
FULL OUTER JOIN monthly_distincts AS md
    ON cs.reporting_month = md.reporting_month
WHERE COALESCE(cs.customers_with_completed_orders, 0) != COALESCE(md.customers_with_completed_orders, 0)
   OR COALESCE(cs.new_customers, 0) != COALESCE(md.new_customers, 0)
   OR COALESCE(cs.returning_customers, 0) != COALESCE(md.returning_customers, 0)
ORDER BY reporting_month;


-- 5) Total customer-base tieout by month end
WITH order_base AS (
    SELECT
        customer_email,
        DATE(created_at_ts) AS order_date
    FROM `mischief-made-analytics.marts.fct_orders`
    WHERE customer_email IS NOT NULL
      AND TRIM(customer_email) <> ''
      AND created_at_ts IS NOT NULL
      AND is_suspect_historical_timing = FALSE
      AND cancelled_at_ts IS NULL
      AND LOWER(COALESCE(financial_status, '')) NOT IN ('voided', 'cancelled')
),

month_spine AS (
    SELECT DISTINCT
        DATE_TRUNC(order_date, MONTH) AS reporting_month
    FROM order_base
),

source_totals AS (
    SELECT
        ms.reporting_month,
        COUNT(DISTINCT ob.customer_email) AS total_customers
    FROM month_spine AS ms
    LEFT JOIN order_base AS ob
        ON ob.order_date <= LAST_DAY(ms.reporting_month)
    GROUP BY ms.reporting_month
)

SELECT
    COALESCE(st.reporting_month, cs.reporting_month) AS reporting_month,
    st.total_customers AS source_total_customers,
    cs.total_customers AS summary_total_customers
FROM source_totals AS st
FULL OUTER JOIN `mischief-made-analytics.marts.anl_customer_summary` AS cs
    ON st.reporting_month = cs.reporting_month
WHERE COALESCE(st.total_customers, 0) != COALESCE(cs.total_customers, 0)
ORDER BY reporting_month;


-- 6) New + returning should equal active customers
SELECT
    reporting_month,
    customers_with_completed_orders,
    new_customers,
    returning_customers,
    new_customers + returning_customers AS new_plus_returning
FROM `mischief-made-analytics.marts.anl_customer_summary`
WHERE new_customers + returning_customers != customers_with_completed_orders
ORDER BY reporting_month;


-- 7) Customer-base segment sums should reconcile to total customers
SELECT
    reporting_month,
    total_customers,
    one_time_customers + repeat_customers AS one_time_plus_repeat,
    active_recent_customers + warm_customers + cooling_off_customers + lapsed_customers AS recency_segment_total,
    high_value_customers + mid_value_customers + low_value_customers AS value_segment_total
FROM `mischief-made-analytics.marts.anl_customer_summary`
WHERE one_time_customers + repeat_customers != total_customers
   OR active_recent_customers + warm_customers + cooling_off_customers + lapsed_customers != total_customers
   OR high_value_customers + mid_value_customers + low_value_customers != total_customers
ORDER BY reporting_month;


-- 8) Loyalty subset sanity checks
SELECT
    reporting_month,
    loyal_customers,
    repeat_customers,
    loyal_high_value_customers,
    high_value_customers
FROM `mischief-made-analytics.marts.anl_customer_summary`
WHERE loyal_customers > repeat_customers
   OR loyal_high_value_customers > loyal_customers
   OR loyal_high_value_customers > high_value_customers
ORDER BY reporting_month;


-- 9) Rate sanity checks
SELECT
    COUNTIF(pct_new_customers < 0 OR pct_new_customers > 1) AS invalid_pct_new_customers_rows,
    COUNTIF(pct_returning_customers < 0 OR pct_returning_customers > 1) AS invalid_pct_returning_customers_rows,
    COUNTIF(repeat_customer_rate < 0 OR repeat_customer_rate > 1) AS invalid_repeat_customer_rate_rows,
    COUNTIF(loyal_customer_rate < 0 OR loyal_customer_rate > 1) AS invalid_loyal_customer_rate_rows,
    COUNTIF(active_customer_rate < 0 OR active_customer_rate > 1) AS invalid_active_customer_rate_rows
FROM `mischief-made-analytics.marts.anl_customer_summary`;


-- 10) Negative metric sanity checks
SELECT
    COUNTIF(total_customers < 0) AS negative_total_customers_rows,
    COUNTIF(customers_with_completed_orders < 0) AS negative_active_customers_rows,
    COUNTIF(new_customers < 0) AS negative_new_customers_rows,
    COUNTIF(returning_customers < 0) AS negative_returning_customers_rows,
    COUNTIF(net_revenue_in_month < 0) AS negative_net_revenue_rows
FROM `mischief-made-analytics.marts.anl_customer_summary`;
