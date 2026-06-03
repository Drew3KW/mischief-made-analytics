-- sql/validation/dashboard_mvp_validation.sql
-- Purpose:
-- Validate the Business Dashboard MVP views.
--
-- Scope:
-- - Cross-channel dashboard revenue views
-- - Channel daily dashboard view
-- - Shopify-only product-family dashboard view
-- - Shopify-only customer-health dashboard view
--
-- Notes:
-- - This validation does not test cross-channel customer identity resolution.
-- - This validation does not test cross-channel product-family harmonization.
-- - Those are intentionally deferred.

WITH dashboard_daily AS (
    SELECT *
    FROM `mischief-made-analytics.marts.anl_dashboard_revenue_daily`
),

dashboard_monthly AS (
    SELECT *
    FROM `mischief-made-analytics.marts.anl_dashboard_revenue_monthly`
),

dashboard_channel_daily AS (
    SELECT *
    FROM `mischief-made-analytics.marts.anl_dashboard_channel_daily`
),

dashboard_product_family AS (
    SELECT *
    FROM `mischief-made-analytics.marts.anl_dashboard_product_family_summary`
),

dashboard_customer_health AS (
    SELECT *
    FROM `mischief-made-analytics.marts.anl_dashboard_customer_health`
),

source_daily AS (
    SELECT
        order_date,

        COUNT(DISTINCT cross_channel_order_key) AS submitted_orders,

        COUNT(DISTINCT CASE
            WHEN is_cancelled = FALSE THEN cross_channel_order_key
        END) AS completed_orders,

        ROUND(SUM(CASE
            WHEN is_cancelled = FALSE THEN COALESCE(gross_amount, 0)
            ELSE 0
        END), 2) AS total_gross_revenue,

        ROUND(SUM(CASE
            WHEN is_cancelled = FALSE THEN COALESCE(refund_amount, 0)
            ELSE 0
        END), 2) AS total_refunded_amount,

        ROUND(SUM(CASE
            WHEN is_cancelled = FALSE THEN COALESCE(net_revenue_after_refunds, 0)
            ELSE 0
        END), 2) AS total_net_revenue_after_refunds

    FROM `mischief-made-analytics.marts.fct_cross_channel_orders`
    WHERE order_date IS NOT NULL
    GROUP BY order_date
),

daily_vs_source AS (
    SELECT
        COUNT(*) AS compared_dates,

        COUNTIF(
            COALESCE(d.submitted_orders, -1) != COALESCE(s.submitted_orders, -2)
        ) AS submitted_order_mismatches,

        COUNTIF(
            COALESCE(d.completed_orders, -1) != COALESCE(s.completed_orders, -2)
        ) AS completed_order_mismatches,

        COUNTIF(
            COALESCE(d.total_gross_revenue, -1) != COALESCE(s.total_gross_revenue, -2)
        ) AS gross_revenue_mismatches,

        COUNTIF(
            COALESCE(d.total_refunded_amount, -1) != COALESCE(s.total_refunded_amount, -2)
        ) AS refunded_amount_mismatches,

        COUNTIF(
            COALESCE(d.total_net_revenue_after_refunds, -1)
                != COALESCE(s.total_net_revenue_after_refunds, -2)
        ) AS net_revenue_mismatches

    FROM dashboard_daily AS d
    FULL OUTER JOIN source_daily AS s
        ON d.order_date = s.order_date
),

monthly_from_daily AS (
    SELECT
        DATE_TRUNC(order_date, MONTH) AS order_month,
        SUM(submitted_orders) AS submitted_orders,
        SUM(completed_orders) AS completed_orders,
        ROUND(SUM(total_gross_revenue), 2) AS total_gross_revenue,
        ROUND(SUM(total_refunded_amount), 2) AS total_refunded_amount,
        ROUND(SUM(total_net_revenue_after_refunds), 2) AS total_net_revenue_after_refunds
    FROM dashboard_daily
    GROUP BY DATE_TRUNC(order_date, MONTH)
),

monthly_vs_daily AS (
    SELECT
        COUNT(*) AS compared_months,

        COUNTIF(
            COALESCE(m.submitted_orders, -1) != COALESCE(d.submitted_orders, -2)
        ) AS submitted_order_mismatches,

        COUNTIF(
            COALESCE(m.completed_orders, -1) != COALESCE(d.completed_orders, -2)
        ) AS completed_order_mismatches,

        COUNTIF(
            COALESCE(m.total_gross_revenue, -1) != COALESCE(d.total_gross_revenue, -2)
        ) AS gross_revenue_mismatches,

        COUNTIF(
            COALESCE(m.total_refunded_amount, -1) != COALESCE(d.total_refunded_amount, -2)
        ) AS refunded_amount_mismatches,

        COUNTIF(
            COALESCE(m.total_net_revenue_after_refunds, -1)
                != COALESCE(d.total_net_revenue_after_refunds, -2)
        ) AS net_revenue_mismatches

    FROM dashboard_monthly AS m
    FULL OUTER JOIN monthly_from_daily AS d
        ON m.order_month = d.order_month
),

channel_daily_rollup AS (
    SELECT
        order_date,
        SUM(submitted_orders) AS submitted_orders,
        SUM(completed_orders) AS completed_orders,
        ROUND(SUM(gross_revenue), 2) AS total_gross_revenue,
        ROUND(SUM(refunded_amount), 2) AS total_refunded_amount,
        ROUND(SUM(net_revenue_after_refunds), 2) AS total_net_revenue_after_refunds
    FROM dashboard_channel_daily
    GROUP BY order_date
),

channel_vs_daily AS (
    SELECT
        COUNT(*) AS compared_dates,

        COUNTIF(
            COALESCE(c.submitted_orders, -1) != COALESCE(d.submitted_orders, -2)
        ) AS submitted_order_mismatches,

        COUNTIF(
            COALESCE(c.completed_orders, -1) != COALESCE(d.completed_orders, -2)
        ) AS completed_order_mismatches,

        COUNTIF(
            COALESCE(c.total_gross_revenue, -1) != COALESCE(d.total_gross_revenue, -2)
        ) AS gross_revenue_mismatches,

        COUNTIF(
            COALESCE(c.total_refunded_amount, -1) != COALESCE(d.total_refunded_amount, -2)
        ) AS refunded_amount_mismatches,

        COUNTIF(
            COALESCE(c.total_net_revenue_after_refunds, -1)
                != COALESCE(d.total_net_revenue_after_refunds, -2)
        ) AS net_revenue_mismatches

    FROM channel_daily_rollup AS c
    FULL OUTER JOIN dashboard_daily AS d
        ON c.order_date = d.order_date
),

daily_shape AS (
    SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT order_date) AS distinct_date_count,
        COUNTIF(order_date IS NULL) AS null_order_date_count,
        COUNTIF(completed_orders < 0) AS negative_completed_order_count,
        COUNTIF(total_net_revenue_after_refunds < 0) AS negative_net_revenue_day_count,
        COUNTIF(shopify_net_revenue_share < 0 OR shopify_net_revenue_share > 1) AS invalid_shopify_share_count,
        COUNTIF(etsy_net_revenue_share < 0 OR etsy_net_revenue_share > 1) AS invalid_etsy_share_count
    FROM dashboard_daily
),

monthly_shape AS (
    SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT order_month) AS distinct_month_count,
        COUNTIF(order_month IS NULL) AS null_order_month_count,
        COUNTIF(completed_orders < 0) AS negative_completed_order_count,
        COUNTIF(total_net_revenue_after_refunds < 0) AS negative_net_revenue_month_count,
        COUNTIF(shopify_net_revenue_share < 0 OR shopify_net_revenue_share > 1) AS invalid_shopify_share_count,
        COUNTIF(etsy_net_revenue_share < 0 OR etsy_net_revenue_share > 1) AS invalid_etsy_share_count
    FROM dashboard_monthly
),

channel_shape AS (
    SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT CONCAT(CAST(order_date AS STRING), ':', channel)) AS distinct_date_channel_count,
        COUNTIF(order_date IS NULL) AS null_order_date_count,
        COUNTIF(channel IS NULL OR TRIM(channel) = '') AS null_channel_count,
        COUNTIF(completed_orders < 0) AS negative_completed_order_count
    FROM dashboard_channel_daily
),

product_family_shape AS (
    SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT product_family_key) AS distinct_product_family_key_count,
        COUNTIF(product_family_key IS NULL OR TRIM(product_family_key) = '') AS null_product_family_key_count,
        COUNTIF(product_family_name IS NULL OR TRIM(product_family_name) = '') AS null_product_family_name_count,
        COUNTIF(dashboard_scope != 'shopify_only') AS invalid_dashboard_scope_count,
        COUNTIF(lifetime_gross_family_revenue < 0) AS negative_gross_family_revenue_count
    FROM dashboard_product_family
),

customer_health_shape AS (
    SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT reporting_month) AS distinct_reporting_month_count,
        COUNTIF(reporting_month IS NULL) AS null_reporting_month_count,
        COUNTIF(dashboard_scope != 'shopify_only') AS invalid_dashboard_scope_count,
        COUNTIF(total_customers < 0) AS negative_total_customer_count,
        COUNTIF(customers_with_completed_orders < 0) AS negative_active_customer_count
    FROM dashboard_customer_health
),

validation_results AS (
    SELECT
        'dashboard_daily_row_count' AS check_name,
        CAST(row_count AS STRING) AS result_value,
        '> 0' AS expected_value,
        CASE WHEN row_count > 0 THEN 'PASS' ELSE 'FAIL' END AS check_status,
        'Daily dashboard view should contain rows.' AS notes
    FROM daily_shape

    UNION ALL

    SELECT
        'dashboard_daily_duplicate_date_count',
        CAST(row_count - distinct_date_count AS STRING),
        '0',
        CASE WHEN row_count - distinct_date_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Daily dashboard view should have one row per date.'
    FROM daily_shape

    UNION ALL

    SELECT
        'dashboard_daily_null_date_count',
        CAST(null_order_date_count AS STRING),
        '0',
        CASE WHEN null_order_date_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Daily dashboard dates should not be null.'
    FROM daily_shape

    UNION ALL

    SELECT
        'dashboard_daily_invalid_revenue_share_count',
        CAST(invalid_shopify_share_count + invalid_etsy_share_count AS STRING),
        '0',
        CASE WHEN invalid_shopify_share_count + invalid_etsy_share_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Daily revenue share values should stay between 0 and 1.'
    FROM daily_shape

    UNION ALL

    SELECT
        'dashboard_daily_vs_source_submitted_orders',
        CAST(submitted_order_mismatches AS STRING),
        '0',
        CASE WHEN submitted_order_mismatches = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Daily submitted orders should match fct_cross_channel_orders.'
    FROM daily_vs_source

    UNION ALL

    SELECT
        'dashboard_daily_vs_source_completed_orders',
        CAST(completed_order_mismatches AS STRING),
        '0',
        CASE WHEN completed_order_mismatches = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Daily completed orders should match fct_cross_channel_orders.'
    FROM daily_vs_source

    UNION ALL

    SELECT
        'dashboard_daily_vs_source_net_revenue',
        CAST(net_revenue_mismatches AS STRING),
        '0',
        CASE WHEN net_revenue_mismatches = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Daily net revenue should match fct_cross_channel_orders.'
    FROM daily_vs_source

    UNION ALL

    SELECT
        'dashboard_monthly_row_count',
        CAST(row_count AS STRING),
        '> 0',
        CASE WHEN row_count > 0 THEN 'PASS' ELSE 'FAIL' END,
        'Monthly dashboard view should contain rows.'
    FROM monthly_shape

    UNION ALL

    SELECT
        'dashboard_monthly_duplicate_month_count',
        CAST(row_count - distinct_month_count AS STRING),
        '0',
        CASE WHEN row_count - distinct_month_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Monthly dashboard view should have one row per month.'
    FROM monthly_shape

    UNION ALL

    SELECT
        'dashboard_monthly_vs_daily_net_revenue',
        CAST(net_revenue_mismatches AS STRING),
        '0',
        CASE WHEN net_revenue_mismatches = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Monthly dashboard net revenue should tie to daily dashboard totals.'
    FROM monthly_vs_daily

    UNION ALL

    SELECT
        'dashboard_channel_daily_row_count',
        CAST(row_count AS STRING),
        '> 0',
        CASE WHEN row_count > 0 THEN 'PASS' ELSE 'FAIL' END,
        'Channel daily dashboard view should contain rows.'
    FROM channel_shape

    UNION ALL

    SELECT
        'dashboard_channel_daily_duplicate_date_channel_count',
        CAST(row_count - distinct_date_channel_count AS STRING),
        '0',
        CASE WHEN row_count - distinct_date_channel_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Channel daily dashboard view should have one row per date and channel.'
    FROM channel_shape

    UNION ALL

    SELECT
        'dashboard_channel_daily_vs_dashboard_daily_net_revenue',
        CAST(net_revenue_mismatches AS STRING),
        '0',
        CASE WHEN net_revenue_mismatches = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Channel daily net revenue should tie to the dashboard daily total.'
    FROM channel_vs_daily

    UNION ALL

    SELECT
        'dashboard_product_family_row_count',
        CAST(row_count AS STRING),
        '> 0',
        CASE WHEN row_count > 0 THEN 'PASS' ELSE 'FAIL' END,
        'Product-family dashboard view should contain rows.'
    FROM product_family_shape

    UNION ALL

    SELECT
        'dashboard_product_family_duplicate_key_count',
        CAST(row_count - distinct_product_family_key_count AS STRING),
        '0',
        CASE WHEN row_count - distinct_product_family_key_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Product-family dashboard view should have one row per product family key.'
    FROM product_family_shape

    UNION ALL

    SELECT
        'dashboard_product_family_scope_check',
        CAST(invalid_dashboard_scope_count AS STRING),
        '0',
        CASE WHEN invalid_dashboard_scope_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Product-family dashboard view should be explicitly scoped as Shopify-only.'
    FROM product_family_shape

    UNION ALL

    SELECT
        'dashboard_customer_health_row_count',
        CAST(row_count AS STRING),
        '> 0',
        CASE WHEN row_count > 0 THEN 'PASS' ELSE 'FAIL' END,
        'Customer-health dashboard view should contain rows.'
    FROM customer_health_shape

    UNION ALL

    SELECT
        'dashboard_customer_health_duplicate_month_count',
        CAST(row_count - distinct_reporting_month_count AS STRING),
        '0',
        CASE WHEN row_count - distinct_reporting_month_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Customer-health dashboard view should have one row per reporting month.'
    FROM customer_health_shape

    UNION ALL

    SELECT
        'dashboard_customer_health_scope_check',
        CAST(invalid_dashboard_scope_count AS STRING),
        '0',
        CASE WHEN invalid_dashboard_scope_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Customer-health dashboard view should be explicitly scoped as Shopify-only.'
    FROM customer_health_shape
)

SELECT
    check_name,
    result_value,
    expected_value,
    check_status,
    notes
FROM validation_results
ORDER BY
    CASE check_status
        WHEN 'FAIL' THEN 1
        WHEN 'REVIEW' THEN 2
        WHEN 'INFO' THEN 3
        WHEN 'PASS' THEN 4
        ELSE 5
    END,
    check_name;