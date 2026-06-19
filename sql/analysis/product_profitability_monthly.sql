-- sql/analysis/product_profitability_monthly.sql
-- View: marts.anl_product_profitability_monthly
-- Grain:
-- One row per month, channel, product family, and COGS resolution grouping.
--
-- Purpose:
-- Track monthly estimated product profitability with explicit COGS coverage.

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_product_profitability_monthly` AS

WITH order_items AS (
    SELECT *
    FROM `mischief-made-analytics.marts.fct_cross_channel_order_items`
    WHERE order_date IS NOT NULL
),

summary AS (
    SELECT
        DATE_TRUNC(order_date, MONTH) AS order_month,
        channel,
        cross_channel_product_family_key,
        product_family_key,
        product_family_name,
        item_product_type_group,
        item_product_subtype_group,

        COUNT(*) AS order_item_rows,
        COUNT(DISTINCT cross_channel_order_key) AS order_count,
        SUM(quantity) AS units_sold,

        ROUND(SUM(gross_item_revenue), 2) AS gross_item_revenue,
        ROUND(SUM(net_item_revenue_before_refunds), 2) AS net_item_revenue_before_refunds,

        COUNTIF(cogs_resolution_status = 'accepted') AS rows_with_accepted_cogs,
        COUNTIF(cogs_resolution_status != 'accepted') AS rows_without_accepted_cogs,

        ROUND(
            SUM(IF(cogs_resolution_status = 'accepted', net_item_revenue_before_refunds, 0)),
            2
        ) AS revenue_with_accepted_cogs,

        ROUND(
            SUM(IF(cogs_resolution_status != 'accepted', net_item_revenue_before_refunds, 0)),
            2
        ) AS revenue_without_accepted_cogs,

        ROUND(SUM(COALESCE(estimated_item_cogs, 0)), 2) AS estimated_item_cogs,

        ROUND(SUM(COALESCE(estimated_gross_profit_before_fees, 0)), 2) AS estimated_gross_profit_before_fees,

        COUNTIF(cogs_match_grain = 'sku') AS sku_cogs_match_rows,
        COUNTIF(cogs_match_grain = 'manual_product_family_override') AS manual_override_cogs_match_rows,
        COUNTIF(cogs_match_grain = 'product_family') AS product_family_cogs_match_rows,
        COUNTIF(cogs_match_grain = 'name_type') AS name_type_cogs_match_rows

    FROM order_items
    GROUP BY
        order_month,
        channel,
        cross_channel_product_family_key,
        product_family_key,
        product_family_name,
        item_product_type_group,
        item_product_subtype_group
)

SELECT
    order_month,
    channel,
    cross_channel_product_family_key,
    product_family_key,
    product_family_name,
    item_product_type_group,
    item_product_subtype_group,

    order_item_rows,
    order_count,
    units_sold,

    gross_item_revenue,
    net_item_revenue_before_refunds,

    rows_with_accepted_cogs,
    rows_without_accepted_cogs,

    ROUND(SAFE_DIVIDE(rows_with_accepted_cogs, order_item_rows), 4) AS accepted_cogs_row_coverage,

    revenue_with_accepted_cogs,
    revenue_without_accepted_cogs,

    ROUND(
        SAFE_DIVIDE(revenue_with_accepted_cogs, net_item_revenue_before_refunds),
        4
    ) AS accepted_cogs_revenue_coverage,

    estimated_item_cogs,
    estimated_gross_profit_before_fees,

    ROUND(
        SAFE_DIVIDE(estimated_gross_profit_before_fees, revenue_with_accepted_cogs),
        4
    ) AS estimated_gross_margin_before_fees,

    sku_cogs_match_rows,
    manual_override_cogs_match_rows,
    product_family_cogs_match_rows,
    name_type_cogs_match_rows

FROM summary;