-- sql/analysis/family_summary.sql
-- Purpose:
-- Dashboard-ready monthly family summary view for Analysis Pack v1.
--
-- Grain:
-- One row per reporting_month per product_family_key.
--
-- Notes:
-- - Uses trusted dates by default
-- - Builds monthly family metrics directly from trusted fct_orders + fct_order_items
-- - Reuses all-time family customer mix context from marts.anl_product_family_customer_mix
-- - Computes monthly distinct family customer counts directly from trusted orders
-- - Filters to core families via shared upstream family metadata
-- - Adds BI-friendly share-of-business and MoM trend fields

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_family_summary` AS

WITH trusted_family_lines AS (
    SELECT
        DATE_TRUNC(DATE(o.created_at_ts), MONTH) AS reporting_month,
        o.order_number,
        o.customer_email,
        pfm.product_family_key,
        dpf.product_family_name,
        oi.quantity,
        COALESCE(oi.gross_item_revenue, 0) AS gross_item_revenue,
        COALESCE(oi.net_item_revenue_before_refunds, 0) AS net_item_revenue_before_refunds
    FROM `mischief-made-analytics.marts.fct_order_items` AS oi
    INNER JOIN `mischief-made-analytics.marts.fct_orders` AS o
        ON oi.order_number = o.order_number
    INNER JOIN `mischief-made-analytics.marts.product_family_map` AS pfm
        ON oi.product_key = pfm.product_key
    LEFT JOIN `mischief-made-analytics.marts.dim_product_families` AS dpf
        ON pfm.product_family_key = dpf.product_family_key
    WHERE o.created_at_ts IS NOT NULL
      AND o.customer_email IS NOT NULL
      AND TRIM(o.customer_email) <> ''
      AND o.cancelled_at_ts IS NULL
      AND LOWER(COALESCE(o.financial_status, '')) NOT IN ('voided', 'cancelled')
      AND o.is_suspect_historical_timing = FALSE
      AND pfm.product_family_key IS NOT NULL
      AND dpf.product_family_name IS NOT NULL
      AND TRIM(dpf.product_family_name) <> ''
      AND dpf.is_core_family = TRUE
),

monthly_family_base AS (
    SELECT
        reporting_month,
        product_family_key,
        product_family_name,
        COUNT(DISTINCT order_number) AS orders_with_family,
        SUM(quantity) AS units_sold,
        ROUND(SUM(gross_item_revenue), 2) AS gross_family_revenue,
        ROUND(SUM(net_item_revenue_before_refunds), 2) AS net_family_revenue_before_refunds
    FROM trusted_family_lines
    GROUP BY
        reporting_month,
        product_family_key,
        product_family_name
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

monthly_family_customer_counts AS (
    SELECT
        tfl.reporting_month,
        tfl.product_family_key,
        COUNT(DISTINCT tfl.customer_email) AS customers_with_family_orders,
        COUNT(DISTINCT CASE
            WHEN cfo.first_order_month = tfl.reporting_month
            THEN tfl.customer_email
        END) AS new_customers,
        COUNT(DISTINCT CASE
            WHEN cfo.first_order_month < tfl.reporting_month
            THEN tfl.customer_email
        END) AS returning_customers
    FROM trusted_family_lines AS tfl
    LEFT JOIN customer_first_order AS cfo
        ON tfl.customer_email = cfo.customer_email
    GROUP BY
        tfl.reporting_month,
        tfl.product_family_key
),

family_customer_mix AS (
    SELECT
        product_family_key,
        product_family_name,
        customers_who_bought_family,
        one_time_customers_who_bought_family,
        repeat_customers_who_bought_family,
        pct_repeat_customers,
        orders_containing_family AS lifetime_orders_with_family,
        units_sold AS lifetime_units_sold,
        gross_family_revenue AS lifetime_gross_family_revenue,
        net_family_revenue_before_refunds AS lifetime_net_family_revenue_before_refunds,
        avg_customer_lifetime_revenue,
        avg_customer_lifetime_orders,
        customers_first_buying_this_family,
        pct_of_family_customers_first_buying_this_family
    FROM `mischief-made-analytics.marts.anl_product_family_customer_mix`
),

month_totals AS (
    SELECT
        reporting_month,
        SUM(orders_with_family) AS month_orders_with_family,
        SUM(units_sold) AS month_units_sold,
        ROUND(SUM(gross_family_revenue), 2) AS month_gross_family_revenue,
        ROUND(SUM(net_family_revenue_before_refunds), 2) AS month_net_family_revenue_before_refunds,
        SUM(customers_with_family_orders) AS month_customers_with_family_orders
    FROM (
        SELECT
            mfb.reporting_month,
            mfb.orders_with_family,
            mfb.units_sold,
            mfb.gross_family_revenue,
            mfb.net_family_revenue_before_refunds,
            COALESCE(mfcc.customers_with_family_orders, 0) AS customers_with_family_orders
        FROM monthly_family_base AS mfb
        LEFT JOIN monthly_family_customer_counts AS mfcc
            ON mfb.reporting_month = mfcc.reporting_month
           AND mfb.product_family_key = mfcc.product_family_key
    )
    GROUP BY reporting_month
),

enriched AS (
    SELECT
        mfb.reporting_month,
        mfb.product_family_key,
        mfb.product_family_name,
        mfb.orders_with_family,
        mfb.units_sold,
        mfb.gross_family_revenue,
        mfb.net_family_revenue_before_refunds,
        COALESCE(mfcc.customers_with_family_orders, 0) AS customers_with_family_orders,
        COALESCE(mfcc.new_customers, 0) AS new_customers,
        COALESCE(mfcc.returning_customers, 0) AS returning_customers,

        COALESCE(fcm.customers_who_bought_family, 0) AS customers_who_bought_family,
        COALESCE(fcm.one_time_customers_who_bought_family, 0) AS one_time_customers_who_bought_family,
        COALESCE(fcm.repeat_customers_who_bought_family, 0) AS repeat_customers_who_bought_family,
        COALESCE(fcm.pct_repeat_customers, 0) AS pct_repeat_customers,
        COALESCE(fcm.lifetime_orders_with_family, 0) AS lifetime_orders_with_family,
        COALESCE(fcm.lifetime_units_sold, 0) AS lifetime_units_sold,
        COALESCE(fcm.lifetime_gross_family_revenue, 0) AS lifetime_gross_family_revenue,
        COALESCE(fcm.lifetime_net_family_revenue_before_refunds, 0) AS lifetime_net_family_revenue_before_refunds,
        COALESCE(fcm.avg_customer_lifetime_revenue, 0) AS avg_customer_lifetime_revenue,
        COALESCE(fcm.avg_customer_lifetime_orders, 0) AS avg_customer_lifetime_orders,
        COALESCE(fcm.customers_first_buying_this_family, 0) AS customers_first_buying_this_family,
        COALESCE(fcm.pct_of_family_customers_first_buying_this_family, 0) AS pct_of_family_customers_first_buying_this_family,

        ROUND(SAFE_DIVIDE(mfb.gross_family_revenue, mfb.orders_with_family), 2) AS avg_order_value_for_family,
        ROUND(SAFE_DIVIDE(mfb.units_sold, mfb.orders_with_family), 2) AS avg_units_per_order,
        ROUND(SAFE_DIVIDE(mfb.gross_family_revenue, COALESCE(mfcc.customers_with_family_orders, 0)), 2) AS revenue_per_family_customer,

        ROUND(SAFE_DIVIDE(COALESCE(mfcc.new_customers, 0), COALESCE(mfcc.customers_with_family_orders, 0)), 4) AS new_customer_rate,
        ROUND(SAFE_DIVIDE(COALESCE(mfcc.returning_customers, 0), COALESCE(mfcc.customers_with_family_orders, 0)), 4) AS returning_customer_rate,

        ROUND(SAFE_DIVIDE(mfb.gross_family_revenue, mt.month_gross_family_revenue), 4) AS revenue_share_of_month,
        ROUND(SAFE_DIVIDE(mfb.orders_with_family, mt.month_orders_with_family), 4) AS orders_share_of_month,
        ROUND(SAFE_DIVIDE(COALESCE(mfcc.customers_with_family_orders, 0), mt.month_customers_with_family_orders), 4) AS customers_share_of_month,
        ROUND(SAFE_DIVIDE(mfb.units_sold, mt.month_units_sold), 4) AS units_share_of_month
    FROM monthly_family_base AS mfb
    LEFT JOIN monthly_family_customer_counts AS mfcc
        ON mfb.reporting_month = mfcc.reporting_month
       AND mfb.product_family_key = mfcc.product_family_key
    LEFT JOIN family_customer_mix AS fcm
        ON mfb.product_family_key = fcm.product_family_key
    LEFT JOIN month_totals AS mt
        ON mfb.reporting_month = mt.reporting_month
),

final AS (
    SELECT
        reporting_month,
        product_family_key,
        product_family_name,
        orders_with_family,
        units_sold,
        gross_family_revenue,
        net_family_revenue_before_refunds,
        customers_with_family_orders,
        new_customers,
        returning_customers,
        customers_who_bought_family,
        one_time_customers_who_bought_family,
        repeat_customers_who_bought_family,
        pct_repeat_customers,
        lifetime_orders_with_family,
        lifetime_units_sold,
        lifetime_gross_family_revenue,
        lifetime_net_family_revenue_before_refunds,
        avg_customer_lifetime_revenue,
        avg_customer_lifetime_orders,
        customers_first_buying_this_family,
        pct_of_family_customers_first_buying_this_family,
        avg_order_value_for_family,
        avg_units_per_order,
        revenue_per_family_customer,
        new_customer_rate,
        returning_customer_rate,
        revenue_share_of_month,
        orders_share_of_month,
        customers_share_of_month,
        units_share_of_month,

        LAG(gross_family_revenue) OVER (
            PARTITION BY product_family_key
            ORDER BY reporting_month
        ) AS prior_month_gross_family_revenue,

        gross_family_revenue - LAG(gross_family_revenue) OVER (
            PARTITION BY product_family_key
            ORDER BY reporting_month
        ) AS gross_family_revenue_mom_change,

        ROUND(
            SAFE_DIVIDE(
                gross_family_revenue - LAG(gross_family_revenue) OVER (
                    PARTITION BY product_family_key
                    ORDER BY reporting_month
                ),
                LAG(gross_family_revenue) OVER (
                    PARTITION BY product_family_key
                    ORDER BY reporting_month
                )
            ),
            4
        ) AS gross_family_revenue_mom_pct_change,

        LAG(orders_with_family) OVER (
            PARTITION BY product_family_key
            ORDER BY reporting_month
        ) AS prior_month_orders_with_family,

        orders_with_family - LAG(orders_with_family) OVER (
            PARTITION BY product_family_key
            ORDER BY reporting_month
        ) AS orders_with_family_mom_change,

        ROUND(
            SAFE_DIVIDE(
                orders_with_family - LAG(orders_with_family) OVER (
                    PARTITION BY product_family_key
                    ORDER BY reporting_month
                ),
                LAG(orders_with_family) OVER (
                    PARTITION BY product_family_key
                    ORDER BY reporting_month
                )
            ),
            4
        ) AS orders_with_family_mom_pct_change,

        LAG(customers_with_family_orders) OVER (
            PARTITION BY product_family_key
            ORDER BY reporting_month
        ) AS prior_month_customers_with_family_orders,

        customers_with_family_orders - LAG(customers_with_family_orders) OVER (
            PARTITION BY product_family_key
            ORDER BY reporting_month
        ) AS customers_with_family_orders_mom_change,

        ROUND(
            SAFE_DIVIDE(
                customers_with_family_orders - LAG(customers_with_family_orders) OVER (
                    PARTITION BY product_family_key
                    ORDER BY reporting_month
                ),
                LAG(customers_with_family_orders) OVER (
                    PARTITION BY product_family_key
                    ORDER BY reporting_month
                )
            ),
            4
        ) AS customers_with_family_orders_mom_pct_change,

        CASE
            WHEN gross_family_revenue >= 5000 THEN 'high'
            WHEN gross_family_revenue >= 1500 THEN 'mid'
            ELSE 'low'
        END AS family_revenue_tier,

        CASE
            WHEN customers_with_family_orders >= 40 THEN 'broad'
            WHEN customers_with_family_orders >= 15 THEN 'moderate'
            ELSE 'niche'
        END AS family_customer_reach_tier,

        CASE
            WHEN LAG(gross_family_revenue) OVER (
                PARTITION BY product_family_key
                ORDER BY reporting_month
            ) IS NULL THEN 'newly_tracked'
            WHEN SAFE_DIVIDE(
                gross_family_revenue - LAG(gross_family_revenue) OVER (
                    PARTITION BY product_family_key
                    ORDER BY reporting_month
                ),
                LAG(gross_family_revenue) OVER (
                    PARTITION BY product_family_key
                    ORDER BY reporting_month
                )
            ) >= 0.15 THEN 'growing'
            WHEN SAFE_DIVIDE(
                gross_family_revenue - LAG(gross_family_revenue) OVER (
                    PARTITION BY product_family_key
                    ORDER BY reporting_month
                ),
                LAG(gross_family_revenue) OVER (
                    PARTITION BY product_family_key
                    ORDER BY reporting_month
                )
            ) <= -0.15 THEN 'declining'
            ELSE 'stable'
        END AS family_trend_status
    FROM enriched
)

SELECT
    reporting_month,
    product_family_key,
    product_family_name,
    orders_with_family,
    units_sold,
    gross_family_revenue,
    net_family_revenue_before_refunds,
    customers_with_family_orders,
    new_customers,
    returning_customers,
    customers_who_bought_family,
    one_time_customers_who_bought_family,
    repeat_customers_who_bought_family,
    pct_repeat_customers,
    lifetime_orders_with_family,
    lifetime_units_sold,
    lifetime_gross_family_revenue,
    lifetime_net_family_revenue_before_refunds,
    avg_customer_lifetime_revenue,
    avg_customer_lifetime_orders,
    customers_first_buying_this_family,
    pct_of_family_customers_first_buying_this_family,
    avg_order_value_for_family,
    avg_units_per_order,
    revenue_per_family_customer,
    new_customer_rate,
    returning_customer_rate,
    revenue_share_of_month,
    orders_share_of_month,
    customers_share_of_month,
    units_share_of_month,
    prior_month_gross_family_revenue,
    gross_family_revenue_mom_change,
    gross_family_revenue_mom_pct_change,
    prior_month_orders_with_family,
    orders_with_family_mom_change,
    orders_with_family_mom_pct_change,
    prior_month_customers_with_family_orders,
    customers_with_family_orders_mom_change,
    customers_with_family_orders_mom_pct_change,
    family_revenue_tier,
    family_customer_reach_tier,
    family_trend_status
FROM final
ORDER BY reporting_month, gross_family_revenue DESC, product_family_name;
