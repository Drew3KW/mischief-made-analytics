-- sql/validation/family_summary_validation.sql
-- Purpose:
-- Validation checks for marts.anl_family_summary.

-- 1) Grain check: one row per month per family
SELECT
    reporting_month,
    product_family_key,
    COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.anl_family_summary`
GROUP BY
    reporting_month,
    product_family_key
HAVING COUNT(*) > 1;


-- 2) Null key checks
SELECT
    COUNTIF(reporting_month IS NULL) AS null_reporting_month_rows,
    COUNTIF(product_family_key IS NULL) AS null_product_family_key_rows,
    COUNTIF(product_family_name IS NULL) AS null_product_family_name_rows
FROM `mischief-made-analytics.marts.anl_family_summary`;


-- 3) Revenue / units / orders tieout to monthly family revenue source
SELECT
    COALESCE(fs.reporting_month, pr.order_month) AS reporting_month,
    COALESCE(fs.product_family_key, pr.product_family_key) AS product_family_key,
    fs.product_family_name AS family_summary_name,
    pr.product_family_name AS source_family_name,
    fs.orders_with_family AS summary_orders_with_family,
    pr.orders_containing_family AS source_orders_with_family,
    fs.units_sold AS summary_units_sold,
    pr.units_sold AS source_units_sold,
    fs.gross_family_revenue AS summary_gross_family_revenue,
    pr.gross_family_revenue AS source_gross_family_revenue
FROM `mischief-made-analytics.marts.anl_family_summary` AS fs
FULL OUTER JOIN `mischief-made-analytics.marts.anl_product_revenue_monthly_by_family` AS pr
    ON fs.reporting_month = pr.order_month
   AND fs.product_family_key = pr.product_family_key
WHERE COALESCE(fs.orders_with_family, 0) != COALESCE(pr.orders_containing_family, 0)
   OR COALESCE(fs.units_sold, 0) != COALESCE(pr.units_sold, 0)
   OR ROUND(COALESCE(fs.gross_family_revenue, 0), 2) != ROUND(COALESCE(pr.gross_family_revenue, 0), 2)
ORDER BY reporting_month, product_family_key;


-- 4) Monthly family customer counts and new/returning tieout to source orders
WITH trusted_family_lines_customers AS (
    SELECT
        DATE_TRUNC(DATE(o.created_at_ts), MONTH) AS reporting_month,
        o.customer_email,
        pfm.product_family_key
    FROM `mischief-made-analytics.marts.fct_order_items` AS oi
    INNER JOIN `mischief-made-analytics.marts.fct_orders` AS o
        ON oi.order_number = o.order_number
    INNER JOIN `mischief-made-analytics.marts.product_family_map` AS pfm
        ON oi.product_key = pfm.product_key
    LEFT JOIN `mischief-made-analytics.marts.dim_product_families` AS dpf
        ON pfm.product_family_key = dpf.product_family_key
    WHERE o.customer_email IS NOT NULL
      AND TRIM(o.customer_email) <> ''
      AND o.created_at_ts IS NOT NULL
      AND o.cancelled_at_ts IS NULL
      AND LOWER(COALESCE(o.financial_status, '')) NOT IN ('voided', 'cancelled')
      AND o.is_suspect_historical_timing = FALSE
      AND pfm.product_family_key IS NOT NULL
      AND dpf.product_family_name IS NOT NULL
      AND TRIM(dpf.product_family_name) <> ''
      AND dpf.is_core_family = TRUE
),
customer_first_order AS (
    SELECT
        customer_email,
        DATE_TRUNC(MIN(DATE(created_at_ts)), MONTH) AS first_order_month
    FROM `mischief-made-analytics.marts.fct_orders`
    WHERE customer_email IS NOT NULL
      AND TRIM(customer_email) <> ''
      AND created_at_ts IS NOT NULL
      AND cancelled_at_ts IS NULL
      AND LOWER(COALESCE(financial_status, '')) NOT IN ('voided', 'cancelled')
      AND is_suspect_historical_timing = FALSE
    GROUP BY customer_email
),
source_monthly_distincts AS (
    SELECT
        tflc.reporting_month,
        tflc.product_family_key,
        COUNT(DISTINCT tflc.customer_email) AS customers_with_family_orders,
        COUNT(DISTINCT CASE
            WHEN cfo.first_order_month = tflc.reporting_month THEN tflc.customer_email
        END) AS new_customers,
        COUNT(DISTINCT CASE
            WHEN cfo.first_order_month < tflc.reporting_month THEN tflc.customer_email
        END) AS returning_customers
    FROM trusted_family_lines_customers AS tflc
    LEFT JOIN customer_first_order AS cfo
        ON tflc.customer_email = cfo.customer_email
    GROUP BY
        tflc.reporting_month,
        tflc.product_family_key
)
SELECT
    COALESCE(fs.reporting_month, smd.reporting_month) AS reporting_month,
    COALESCE(fs.product_family_key, smd.product_family_key) AS product_family_key,
    fs.customers_with_family_orders AS summary_customers_with_family_orders,
    smd.customers_with_family_orders AS source_customers_with_family_orders,
    fs.new_customers AS summary_new_customers,
    smd.new_customers AS source_new_customers,
    fs.returning_customers AS summary_returning_customers,
    smd.returning_customers AS source_returning_customers
FROM `mischief-made-analytics.marts.anl_family_summary` AS fs
FULL OUTER JOIN source_monthly_distincts AS smd
    ON fs.reporting_month = smd.reporting_month
   AND fs.product_family_key = smd.product_family_key
WHERE COALESCE(fs.customers_with_family_orders, 0) != COALESCE(smd.customers_with_family_orders, 0)
   OR COALESCE(fs.new_customers, 0) != COALESCE(smd.new_customers, 0)
   OR COALESCE(fs.returning_customers, 0) != COALESCE(smd.returning_customers, 0)
ORDER BY reporting_month, product_family_key;


-- 5) Monthly net family revenue tieout to source lines
WITH trusted_family_lines_all AS (
    SELECT
        DATE_TRUNC(DATE(o.created_at_ts), MONTH) AS reporting_month,
        pfm.product_family_key,
        ROUND(SUM(COALESCE(oi.net_item_revenue_before_refunds, 0)), 2) AS source_net_family_revenue_before_refunds
    FROM `mischief-made-analytics.marts.fct_order_items` AS oi
    INNER JOIN `mischief-made-analytics.marts.fct_orders` AS o
        ON oi.order_number = o.order_number
    INNER JOIN `mischief-made-analytics.marts.product_family_map` AS pfm
        ON oi.product_key = pfm.product_key
    LEFT JOIN `mischief-made-analytics.marts.dim_product_families` AS dpf
        ON pfm.product_family_key = dpf.product_family_key
    WHERE o.created_at_ts IS NOT NULL
      AND o.cancelled_at_ts IS NULL
      AND LOWER(COALESCE(o.financial_status, '')) NOT IN ('voided', 'cancelled')
      AND o.is_suspect_historical_timing = FALSE
      AND pfm.product_family_key IS NOT NULL
      AND dpf.product_family_name IS NOT NULL
      AND TRIM(dpf.product_family_name) <> ''
      AND dpf.is_core_family = TRUE
    GROUP BY
        DATE_TRUNC(DATE(o.created_at_ts), MONTH),
        pfm.product_family_key
)
SELECT
    COALESCE(fs.reporting_month, tfl.reporting_month) AS reporting_month,
    COALESCE(fs.product_family_key, tfl.product_family_key) AS product_family_key,
    fs.net_family_revenue_before_refunds AS summary_net_family_revenue_before_refunds,
    tfl.source_net_family_revenue_before_refunds
FROM `mischief-made-analytics.marts.anl_family_summary` AS fs
FULL OUTER JOIN trusted_family_lines_all AS tfl
    ON fs.reporting_month = tfl.reporting_month
   AND fs.product_family_key = tfl.product_family_key
WHERE ROUND(COALESCE(fs.net_family_revenue_before_refunds, 0), 2)
   != ROUND(COALESCE(tfl.source_net_family_revenue_before_refunds, 0), 2)
ORDER BY reporting_month, product_family_key;


-- 6) Monthly share-of-business should sum to ~1 across families
-- Note:
-- Share fields are rounded, so use a practical tolerance rather than an ultra-tight one.
SELECT
    reporting_month,
    ROUND(SUM(revenue_share_of_month), 6) AS revenue_share_sum,
    ROUND(SUM(orders_share_of_month), 6) AS orders_share_sum,
    ROUND(SUM(customers_share_of_month), 6) AS customers_share_sum,
    ROUND(SUM(units_share_of_month), 6) AS units_share_sum
FROM `mischief-made-analytics.marts.anl_family_summary`
GROUP BY reporting_month
HAVING ABS(ROUND(SUM(revenue_share_of_month), 6) - 1) > 0.01
    OR ABS(ROUND(SUM(orders_share_of_month), 6) - 1) > 0.01
    OR ABS(ROUND(SUM(customers_share_of_month), 6) - 1) > 0.01
    OR ABS(ROUND(SUM(units_share_of_month), 6) - 1) > 0.01
ORDER BY reporting_month;


-- 7) New + returning should equal monthly family customers
SELECT
    reporting_month,
    product_family_key,
    customers_with_family_orders,
    new_customers,
    returning_customers,
    new_customers + returning_customers AS new_plus_returning
FROM `mischief-made-analytics.marts.anl_family_summary`
WHERE new_customers + returning_customers != customers_with_family_orders
ORDER BY reporting_month, product_family_key;


-- 8) Rate sanity checks
SELECT
    COUNTIF(new_customer_rate < 0 OR new_customer_rate > 1) AS invalid_new_customer_rate_rows,
    COUNTIF(returning_customer_rate < 0 OR returning_customer_rate > 1) AS invalid_returning_customer_rate_rows,
    COUNTIF(pct_repeat_customers < 0 OR pct_repeat_customers > 1) AS invalid_pct_repeat_customers_rows,
    COUNTIF(pct_of_family_customers_first_buying_this_family < 0 OR pct_of_family_customers_first_buying_this_family > 1) AS invalid_pct_first_family_rows,
    COUNTIF(revenue_share_of_month < 0 OR revenue_share_of_month > 1) AS invalid_revenue_share_rows,
    COUNTIF(orders_share_of_month < 0 OR orders_share_of_month > 1) AS invalid_orders_share_rows,
    COUNTIF(customers_share_of_month < 0 OR customers_share_of_month > 1) AS invalid_customers_share_rows,
    COUNTIF(units_share_of_month < 0 OR units_share_of_month > 1) AS invalid_units_share_rows
FROM `mischief-made-analytics.marts.anl_family_summary`;


-- 9) Negative metric sanity checks
SELECT
    COUNTIF(orders_with_family < 0) AS negative_orders_rows,
    COUNTIF(units_sold < 0) AS negative_units_rows,
    COUNTIF(gross_family_revenue < 0) AS negative_gross_family_revenue_rows,
    COUNTIF(net_family_revenue_before_refunds < 0) AS negative_net_family_revenue_rows,
    COUNTIF(customers_with_family_orders < 0) AS negative_customers_rows,
    COUNTIF(new_customers < 0) AS negative_new_customers_rows,
    COUNTIF(returning_customers < 0) AS negative_returning_customers_rows
FROM `mischief-made-analytics.marts.anl_family_summary`;


-- 10) Lifetime subset sanity checks
SELECT
    product_family_key,
    product_family_name,
    customers_who_bought_family,
    one_time_customers_who_bought_family,
    repeat_customers_who_bought_family
FROM `mischief-made-analytics.marts.anl_family_summary`
WHERE one_time_customers_who_bought_family + repeat_customers_who_bought_family > customers_who_bought_family
ORDER BY product_family_name;


-- 11) Trend classification sanity check
SELECT
    reporting_month,
    product_family_key,
    product_family_name,
    gross_family_revenue,
    prior_month_gross_family_revenue,
    gross_family_revenue_mom_pct_change,
    family_trend_status
FROM `mischief-made-analytics.marts.anl_family_summary`
WHERE (family_trend_status = 'growing' AND COALESCE(gross_family_revenue_mom_pct_change, 0) < 0.15)
   OR (family_trend_status = 'declining' AND COALESCE(gross_family_revenue_mom_pct_change, 0) > -0.15)
   OR (family_trend_status = 'stable'
       AND prior_month_gross_family_revenue IS NOT NULL
       AND (gross_family_revenue_mom_pct_change >= 0.15 OR gross_family_revenue_mom_pct_change <= -0.15))
ORDER BY reporting_month, product_family_key;


-- 12) Non-core families should never appear in family_summary
SELECT
    fs.reporting_month,
    fs.product_family_key,
    fs.product_family_name,
    dpf.family_reporting_category,
    dpf.family_exclusion_reason
FROM `mischief-made-analytics.marts.anl_family_summary` AS fs
INNER JOIN `mischief-made-analytics.marts.dim_product_families` AS dpf
    ON fs.product_family_key = dpf.product_family_key
WHERE dpf.is_core_family = FALSE
ORDER BY fs.reporting_month, fs.product_family_name;
