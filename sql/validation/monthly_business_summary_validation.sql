-- sql/validation/monthly_business_summary_validation.sql
-- Purpose:
-- Validation checks for marts.anl_monthly_business_summary.

-- 1) Grain check: one row per month
SELECT
    order_month,
    COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.anl_monthly_business_summary`
GROUP BY order_month
HAVING COUNT(*) > 1;

-- 2) Null month check
SELECT
    COUNT(*) AS null_order_month_rows
FROM `mischief-made-analytics.marts.anl_monthly_business_summary`
WHERE order_month IS NULL;

-- 3) Additive metric tieout to daily summary
WITH daily_rollup AS (
    SELECT
        DATE_TRUNC(order_date, MONTH) AS order_month,
        SUM(submitted_orders) AS submitted_orders,
        SUM(completed_orders) AS completed_orders,
        SUM(cancelled_orders) AS cancelled_orders,
        SUM(units_sold) AS units_sold,
        SUM(customers_submitting_orders) AS customers_submitting_orders,
        SUM(customers_with_completed_orders) AS customers_with_completed_orders,
        SUM(new_customers) AS new_customers,
        SUM(returning_customers) AS returning_customers,
        ROUND(SUM(gross_revenue), 2) AS gross_revenue,
        ROUND(SUM(refunded_amount), 2) AS refunded_amount,
        ROUND(SUM(net_revenue_after_refunds), 2) AS net_revenue_after_refunds,
        ROUND(SUM(gross_item_revenue), 2) AS gross_item_revenue,
        ROUND(SUM(net_item_revenue_before_refunds), 2) AS net_item_revenue_before_refunds
    FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
    GROUP BY DATE_TRUNC(order_date, MONTH)
),
monthly AS (
    SELECT
        order_month,
        submitted_orders,
        completed_orders,
        cancelled_orders,
        units_sold,
        customers_submitting_orders,
        customers_with_completed_orders,
        new_customers,
        returning_customers,
        gross_revenue,
        refunded_amount,
        net_revenue_after_refunds,
        gross_item_revenue,
        net_item_revenue_before_refunds
    FROM `mischief-made-analytics.marts.anl_monthly_business_summary`
)
SELECT
    COALESCE(d.order_month, m.order_month) AS order_month,
    d.submitted_orders AS daily_submitted_orders,
    m.submitted_orders AS monthly_submitted_orders,
    d.completed_orders AS daily_completed_orders,
    m.completed_orders AS monthly_completed_orders,
    d.cancelled_orders AS daily_cancelled_orders,
    m.cancelled_orders AS monthly_cancelled_orders,
    d.units_sold AS daily_units_sold,
    m.units_sold AS monthly_units_sold,
    d.customers_submitting_orders AS daily_customers_submitting_orders,
    m.customers_submitting_orders AS monthly_customers_submitting_orders,
    d.customers_with_completed_orders AS daily_customers_with_completed_orders,
    m.customers_with_completed_orders AS monthly_customers_with_completed_orders,
    d.new_customers AS daily_new_customers,
    m.new_customers AS monthly_new_customers,
    d.returning_customers AS daily_returning_customers,
    m.returning_customers AS monthly_returning_customers,
    d.gross_revenue AS daily_gross_revenue,
    m.gross_revenue AS monthly_gross_revenue,
    d.refunded_amount AS daily_refunded_amount,
    m.refunded_amount AS monthly_refunded_amount,
    d.net_revenue_after_refunds AS daily_net_revenue_after_refunds,
    m.net_revenue_after_refunds AS monthly_net_revenue_after_refunds
FROM daily_rollup AS d
FULL OUTER JOIN monthly AS m
    ON d.order_month = m.order_month
WHERE COALESCE(d.submitted_orders, 0) != COALESCE(m.submitted_orders, 0)
   OR COALESCE(d.completed_orders, 0) != COALESCE(m.completed_orders, 0)
   OR COALESCE(d.cancelled_orders, 0) != COALESCE(m.cancelled_orders, 0)
   OR COALESCE(d.units_sold, 0) != COALESCE(m.units_sold, 0)
   OR COALESCE(d.customers_submitting_orders, 0) != COALESCE(m.customers_submitting_orders, 0)
   OR COALESCE(d.customers_with_completed_orders, 0) != COALESCE(m.customers_with_completed_orders, 0)
   OR COALESCE(d.new_customers, 0) != COALESCE(m.new_customers, 0)
   OR COALESCE(d.returning_customers, 0) != COALESCE(m.returning_customers, 0)
   OR COALESCE(d.gross_revenue, 0) != COALESCE(m.gross_revenue, 0)
   OR COALESCE(d.refunded_amount, 0) != COALESCE(m.refunded_amount, 0)
   OR COALESCE(d.net_revenue_after_refunds, 0) != COALESCE(m.net_revenue_after_refunds, 0)
ORDER BY order_month;

-- 4) Recomputed blended KPI check
WITH expected AS (
    SELECT
        order_month,
        ROUND(SAFE_DIVIDE(gross_revenue, completed_orders), 2) AS expected_avg_order_value,
        ROUND(SAFE_DIVIDE(units_sold, completed_orders), 2) AS expected_avg_units_per_order,
        ROUND(SAFE_DIVIDE(gross_revenue, customers_with_completed_orders), 2) AS expected_revenue_per_completed_customer,
        ROUND(SAFE_DIVIDE(cancelled_orders, submitted_orders), 4) AS expected_cancellation_rate
    FROM `mischief-made-analytics.marts.anl_monthly_business_summary`
),
actual AS (
    SELECT
        order_month,
        avg_order_value,
        avg_units_per_order,
        revenue_per_completed_customer,
        cancellation_rate
    FROM `mischief-made-analytics.marts.anl_monthly_business_summary`
)
SELECT
    e.order_month,
    e.expected_avg_order_value,
    a.avg_order_value,
    e.expected_avg_units_per_order,
    a.avg_units_per_order,
    e.expected_revenue_per_completed_customer,
    a.revenue_per_completed_customer,
    e.expected_cancellation_rate,
    a.cancellation_rate
FROM expected AS e
INNER JOIN actual AS a
    ON e.order_month = a.order_month
WHERE e.expected_avg_order_value != a.avg_order_value
   OR e.expected_avg_units_per_order != a.avg_units_per_order
   OR e.expected_revenue_per_completed_customer != a.revenue_per_completed_customer
   OR e.expected_cancellation_rate != a.cancellation_rate
ORDER BY e.order_month;

-- 5) New + returning customer sanity check
SELECT
    order_month,
    customers_with_completed_orders,
    new_customers,
    returning_customers,
    new_customers + returning_customers AS new_plus_returning
FROM `mischief-made-analytics.marts.anl_monthly_business_summary`
WHERE new_customers + returning_customers != customers_with_completed_orders
ORDER BY order_month;

-- 6) MoM lag field sanity check
WITH expected AS (
    SELECT
        order_month,
        LAG(net_revenue_after_refunds) OVER (ORDER BY order_month) AS expected_prior_month_net_revenue,
        LAG(completed_orders) OVER (ORDER BY order_month) AS expected_prior_month_completed_orders,
        LAG(customers_with_completed_orders) OVER (ORDER BY order_month) AS expected_prior_month_customers_with_completed_orders
    FROM `mischief-made-analytics.marts.anl_monthly_business_summary`
)
SELECT
    e.order_month,
    e.expected_prior_month_net_revenue,
    m.prior_month_net_revenue,
    e.expected_prior_month_completed_orders,
    m.prior_month_completed_orders,
    e.expected_prior_month_customers_with_completed_orders,
    m.prior_month_customers_with_completed_orders
FROM expected AS e
INNER JOIN `mischief-made-analytics.marts.anl_monthly_business_summary` AS m
    ON e.order_month = m.order_month
WHERE COALESCE(e.expected_prior_month_net_revenue, -1) != COALESCE(m.prior_month_net_revenue, -1)
   OR COALESCE(e.expected_prior_month_completed_orders, -1) != COALESCE(m.prior_month_completed_orders, -1)
   OR COALESCE(e.expected_prior_month_customers_with_completed_orders, -1) != COALESCE(m.prior_month_customers_with_completed_orders, -1)
ORDER BY e.order_month;

-- 7) Rate sanity checks
SELECT
    COUNTIF(cancellation_rate < 0 OR cancellation_rate > 1) AS invalid_cancellation_rate_rows,
    COUNTIF(refund_rate < 0 OR refund_rate > 1) AS invalid_refund_rate_rows
FROM `mischief-made-analytics.marts.anl_monthly_business_summary`;

-- 8) Negative metric sanity check
SELECT
    COUNTIF(submitted_orders < 0) AS negative_submitted_orders_rows,
    COUNTIF(completed_orders < 0) AS negative_completed_orders_rows,
    COUNTIF(cancelled_orders < 0) AS negative_cancelled_orders_rows,
    COUNTIF(units_sold < 0) AS negative_units_sold_rows,
    COUNTIF(gross_revenue < 0) AS negative_gross_revenue_rows,
    COUNTIF(refunded_amount < 0) AS negative_refunded_amount_rows,
    COUNTIF(net_revenue_after_refunds < 0) AS negative_net_revenue_rows
FROM `mischief-made-analytics.marts.anl_monthly_business_summary`;

-- 9) Full-period tieout to daily summary
WITH monthly AS (
    SELECT
        SUM(submitted_orders) AS submitted_orders,
        SUM(completed_orders) AS completed_orders,
        SUM(cancelled_orders) AS cancelled_orders,
        SUM(units_sold) AS units_sold,
        SUM(customers_submitting_orders) AS customers_submitting_orders,
        SUM(customers_with_completed_orders) AS customers_with_completed_orders,
        SUM(new_customers) AS new_customers,
        SUM(returning_customers) AS returning_customers,
        ROUND(SUM(gross_revenue), 2) AS gross_revenue,
        ROUND(SUM(refunded_amount), 2) AS refunded_amount,
        ROUND(SUM(net_revenue_after_refunds), 2) AS net_revenue_after_refunds
    FROM `mischief-made-analytics.marts.anl_monthly_business_summary`
),
daily AS (
    SELECT
        SUM(submitted_orders) AS submitted_orders,
        SUM(completed_orders) AS completed_orders,
        SUM(cancelled_orders) AS cancelled_orders,
        SUM(units_sold) AS units_sold,
        SUM(customers_submitting_orders) AS customers_submitting_orders,
        SUM(customers_with_completed_orders) AS customers_with_completed_orders,
        SUM(new_customers) AS new_customers,
        SUM(returning_customers) AS returning_customers,
        ROUND(SUM(gross_revenue), 2) AS gross_revenue,
        ROUND(SUM(refunded_amount), 2) AS refunded_amount,
        ROUND(SUM(net_revenue_after_refunds), 2) AS net_revenue_after_refunds
    FROM `mischief-made-analytics.marts.anl_daily_kpi_summary`
)
SELECT
    m.submitted_orders AS monthly_submitted_orders,
    d.submitted_orders AS daily_submitted_orders,
    m.completed_orders AS monthly_completed_orders,
    d.completed_orders AS daily_completed_orders,
    m.cancelled_orders AS monthly_cancelled_orders,
    d.cancelled_orders AS daily_cancelled_orders,
    m.units_sold AS monthly_units_sold,
    d.units_sold AS daily_units_sold,
    m.customers_submitting_orders AS monthly_customers_submitting_orders,
    d.customers_submitting_orders AS daily_customers_submitting_orders,
    m.customers_with_completed_orders AS monthly_customers_with_completed_orders,
    d.customers_with_completed_orders AS daily_customers_with_completed_orders,
    m.new_customers AS monthly_new_customers,
    d.new_customers AS daily_new_customers,
    m.returning_customers AS monthly_returning_customers,
    d.returning_customers AS daily_returning_customers,
    m.gross_revenue AS monthly_gross_revenue,
    d.gross_revenue AS daily_gross_revenue,
    m.refunded_amount AS monthly_refunded_amount,
    d.refunded_amount AS daily_refunded_amount,
    m.net_revenue_after_refunds AS monthly_net_revenue_after_refunds,
    d.net_revenue_after_refunds AS daily_net_revenue_after_refunds
FROM monthly AS m
CROSS JOIN daily AS d;
