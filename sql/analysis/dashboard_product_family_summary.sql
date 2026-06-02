-- sql/analysis/dashboard_product_family_summary.sql
-- Purpose:
-- Dashboard-facing Shopify product-family summary for the Business Dashboard MVP.
--
-- Grain:
-- One row per Shopify product_family_key.
--
-- Notes:
-- - This is intentionally Shopify-only for Milestone 48.
-- - Cross-channel product-family harmonization is deferred.
-- - Built from marts.anl_family_summary, the Milestone 21 dashboard-ready family layer.
-- - Reuses upstream family identity, display naming, and core-family filtering.

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_dashboard_product_family_summary` AS

WITH family_monthly AS (
    SELECT
        *
    FROM `mischief-made-analytics.marts.anl_family_summary`
),

max_month AS (
    SELECT
        MAX(reporting_month) AS latest_reporting_month
    FROM family_monthly
),

family_latest AS (
    SELECT
        *
    FROM family_monthly
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY product_family_key
        ORDER BY reporting_month DESC
    ) = 1
),

recent_windows AS (
    SELECT
        fm.product_family_key,

        ROUND(SUM(CASE
            WHEN fm.reporting_month BETWEEN DATE_SUB(mm.latest_reporting_month, INTERVAL 2 MONTH)
                AND mm.latest_reporting_month
            THEN fm.gross_family_revenue
            ELSE 0
        END), 2) AS revenue_last_3m,

        SUM(CASE
            WHEN fm.reporting_month BETWEEN DATE_SUB(mm.latest_reporting_month, INTERVAL 2 MONTH)
                AND mm.latest_reporting_month
            THEN fm.units_sold
            ELSE 0
        END) AS units_last_3m,

        ROUND(SUM(CASE
            WHEN fm.reporting_month BETWEEN DATE_SUB(mm.latest_reporting_month, INTERVAL 5 MONTH)
                AND DATE_SUB(mm.latest_reporting_month, INTERVAL 3 MONTH)
            THEN fm.gross_family_revenue
            ELSE 0
        END), 2) AS revenue_prior_3m,

        SUM(CASE
            WHEN fm.reporting_month BETWEEN DATE_SUB(mm.latest_reporting_month, INTERVAL 5 MONTH)
                AND DATE_SUB(mm.latest_reporting_month, INTERVAL 3 MONTH)
            THEN fm.units_sold
            ELSE 0
        END) AS units_prior_3m,

        COUNTIF(
            fm.reporting_month BETWEEN DATE_SUB(mm.latest_reporting_month, INTERVAL 2 MONTH)
                AND mm.latest_reporting_month
        ) AS months_with_sales_last_3m,

        COUNTIF(
            fm.reporting_month BETWEEN DATE_SUB(mm.latest_reporting_month, INTERVAL 5 MONTH)
                AND DATE_SUB(mm.latest_reporting_month, INTERVAL 3 MONTH)
        ) AS months_with_sales_prior_3m,

        MIN(fm.reporting_month) AS first_reporting_month_sold,
        MAX(fm.reporting_month) AS most_recent_reporting_month_sold,
        COUNT(*) AS lifetime_months_with_sales

    FROM family_monthly AS fm
    CROSS JOIN max_month AS mm
    GROUP BY fm.product_family_key
),

final AS (
    SELECT
        fl.product_family_key,
        fl.product_family_name,

        'shopify_only' AS dashboard_scope,

        RANK() OVER (
            ORDER BY fl.lifetime_gross_family_revenue DESC
        ) AS lifetime_revenue_rank,

        RANK() OVER (
            ORDER BY fl.lifetime_units_sold DESC
        ) AS lifetime_units_rank,

        RANK() OVER (
            ORDER BY rw.revenue_last_3m DESC
        ) AS recent_3m_revenue_rank,

        rw.first_reporting_month_sold,
        rw.most_recent_reporting_month_sold,
        rw.lifetime_months_with_sales,

        fl.lifetime_orders_with_family,
        fl.lifetime_units_sold,
        fl.lifetime_gross_family_revenue,
        fl.lifetime_net_family_revenue_before_refunds,

        rw.revenue_last_3m,
        rw.units_last_3m,
        rw.revenue_prior_3m,
        rw.units_prior_3m,
        rw.months_with_sales_last_3m,
        rw.months_with_sales_prior_3m,

        ROUND(rw.revenue_last_3m - rw.revenue_prior_3m, 2) AS revenue_change_3m_vs_prior_3m,
        rw.units_last_3m - rw.units_prior_3m AS units_change_3m_vs_prior_3m,

        CASE
            WHEN rw.revenue_prior_3m = 0 AND rw.revenue_last_3m > 0 THEN NULL
            ELSE ROUND(
                SAFE_DIVIDE(
                    rw.revenue_last_3m - rw.revenue_prior_3m,
                    rw.revenue_prior_3m
                ) * 100,
                2
            )
        END AS revenue_pct_change_3m_vs_prior_3m,

        CASE
            WHEN rw.units_prior_3m = 0 AND rw.units_last_3m > 0 THEN NULL
            ELSE ROUND(
                SAFE_DIVIDE(
                    rw.units_last_3m - rw.units_prior_3m,
                    rw.units_prior_3m
                ) * 100,
                2
            )
        END AS units_pct_change_3m_vs_prior_3m,

        CASE
            WHEN rw.revenue_prior_3m = 0 AND rw.revenue_last_3m > 0 THEN 'new_or_returning'
            WHEN rw.revenue_last_3m = 0 AND rw.revenue_prior_3m > 0 THEN 'inactive_recently'
            WHEN rw.revenue_last_3m >= rw.revenue_prior_3m * 1.25 THEN 'rising'
            WHEN rw.revenue_last_3m <= rw.revenue_prior_3m * 0.75 THEN 'declining'
            ELSE 'stable'
        END AS trend_status,

        fl.customers_who_bought_family,
        fl.one_time_customers_who_bought_family,
        fl.repeat_customers_who_bought_family,
        fl.pct_repeat_customers,
        fl.avg_customer_lifetime_revenue,
        fl.avg_customer_lifetime_orders,
        fl.customers_first_buying_this_family,
        fl.pct_of_family_customers_first_buying_this_family,

        fl.reporting_month AS latest_reporting_month,
        fl.gross_family_revenue AS latest_month_gross_family_revenue,
        fl.net_family_revenue_before_refunds AS latest_month_net_family_revenue_before_refunds,
        fl.orders_with_family AS latest_month_orders_with_family,
        fl.units_sold AS latest_month_units_sold,
        fl.customers_with_family_orders AS latest_month_customers_with_family_orders,
        fl.family_revenue_tier,
        fl.family_customer_reach_tier,
        fl.family_trend_status AS latest_month_family_trend_status

    FROM family_latest AS fl
    LEFT JOIN recent_windows AS rw
        ON fl.product_family_key = rw.product_family_key
)

SELECT
    *
FROM final
ORDER BY
    lifetime_revenue_rank,
    product_family_name;