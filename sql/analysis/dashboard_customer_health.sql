-- sql/analysis/dashboard_customer_health.sql
-- Purpose:
-- Dashboard-facing Shopify customer health summary for the Business Dashboard MVP.
--
-- Grain:
-- One row per reporting_month.
--
-- Notes:
-- - This is intentionally Shopify-only for Milestone 48.
-- - Cross-channel customer identity resolution is deferred.
-- - Built from the existing Shopify customer summary view.

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_dashboard_customer_health` AS

SELECT
    reporting_month,

    'shopify_only' AS dashboard_scope,

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

FROM `mischief-made-analytics.marts.anl_customer_summary`
ORDER BY reporting_month;