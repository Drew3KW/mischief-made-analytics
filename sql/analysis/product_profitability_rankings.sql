-- sql/analysis/product_profitability_rankings.sql
-- View: marts.anl_product_profitability_rankings
-- Grain:
-- One row per channel and exact product family name.
--
-- Purpose:
-- Provide a channel-level product-family profitability leaderboard with
-- explicit COGS coverage.
--
-- Notes:
-- - Profitability metrics are estimated gross product profitability before
--   fees, not net profit.
-- - Ad spend is not included.
-- - Unknown product families remain visible in the leaderboard.
-- - Source product-family keys are consolidated for reporting only; this view
--   does not alter source keys or force cross-channel identity matches.
-- - Ratios are calculated after aggregation.

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_product_profitability_rankings` AS

WITH product_family_rollup AS (
    SELECT
        channel,
        COALESCE(product_family_name, 'Unknown Product Family') AS product_family_name,

        COUNT(
            DISTINCT COALESCE(product_family_key, 'unknown_product_family')
        ) AS source_product_family_key_count,
        ARRAY_AGG(
            DISTINCT COALESCE(product_family_key, 'unknown_product_family')
            ORDER BY COALESCE(product_family_key, 'unknown_product_family')
        ) AS source_product_family_keys,

        COUNT(*) AS order_item_rows,
        COUNT(DISTINCT cross_channel_order_key) AS order_count,
        SUM(quantity) AS units_sold,

        SUM(gross_item_revenue) AS gross_item_revenue,
        SUM(net_item_revenue_before_refunds) AS net_item_revenue_before_refunds,

        SUM(
            IF(
                cogs_resolution_status = 'accepted',
                net_item_revenue_before_refunds,
                0
            )
        ) AS revenue_with_accepted_cogs,

        SUM(
            IF(
                cogs_resolution_status = 'accepted',
                0,
                net_item_revenue_before_refunds
            )
        ) AS revenue_without_accepted_cogs,

        SUM(
            IF(
                cogs_resolution_status = 'excluded_from_profit_model',
                net_item_revenue_before_refunds,
                0
            )
        ) AS revenue_excluded_from_profit_model,

        SUM(COALESCE(estimated_item_cogs, 0)) AS estimated_item_cogs,
        SUM(
            COALESCE(estimated_gross_profit_before_fees, 0)
        ) AS estimated_gross_profit_before_fees

    FROM `mischief-made-analytics.marts.fct_cross_channel_order_items`
    GROUP BY
        channel,
        COALESCE(product_family_name, 'Unknown Product Family')
),

product_family_metrics AS (
    SELECT
        channel,
        product_family_name,
        source_product_family_key_count,
        source_product_family_keys,

        order_item_rows,
        order_count,
        units_sold,

        gross_item_revenue,
        net_item_revenue_before_refunds,
        revenue_with_accepted_cogs,
        revenue_without_accepted_cogs,
        revenue_excluded_from_profit_model,
        estimated_item_cogs,
        estimated_gross_profit_before_fees,

        SAFE_DIVIDE(
            estimated_gross_profit_before_fees,
            revenue_with_accepted_cogs
        ) AS estimated_gross_margin_before_fees,

        SAFE_DIVIDE(
            revenue_with_accepted_cogs,
            net_item_revenue_before_refunds
        ) AS accepted_cogs_revenue_coverage,

        CASE
            WHEN SAFE_DIVIDE(
                revenue_with_accepted_cogs,
                net_item_revenue_before_refunds
            ) >= 0.90
                THEN 'high_cogs_coverage'
            WHEN SAFE_DIVIDE(
                revenue_with_accepted_cogs,
                net_item_revenue_before_refunds
            ) >= 0.70
                THEN 'good_cogs_coverage'
            WHEN SAFE_DIVIDE(
                revenue_with_accepted_cogs,
                net_item_revenue_before_refunds
            ) >= 0.50
                THEN 'partial_cogs_coverage'
            WHEN revenue_with_accepted_cogs > 0
                THEN 'limited_cogs_coverage'
            WHEN revenue_excluded_from_profit_model > 0
                THEN 'excluded_from_profit_model'
            ELSE 'no_cogs_coverage'
        END AS profitability_coverage_status,

        COALESCE(
            revenue_with_accepted_cogs > 0
                AND SAFE_DIVIDE(
                    revenue_with_accepted_cogs,
                    net_item_revenue_before_refunds
                ) >= 0.70
                AND order_count >= 5
                AND units_sold >= 5,
            FALSE
        ) AS is_margin_rank_eligible,

        CASE
            WHEN revenue_with_accepted_cogs <= 0
                THEN 'nonpositive_accepted_revenue'
            WHEN SAFE_DIVIDE(
                revenue_with_accepted_cogs,
                net_item_revenue_before_refunds
            ) < 0.70
              OR SAFE_DIVIDE(
                revenue_with_accepted_cogs,
                net_item_revenue_before_refunds
            ) IS NULL
                THEN 'insufficient_cogs_coverage'
            WHEN order_count < 5 OR units_sold < 5
                THEN 'insufficient_sales_volume'
            ELSE 'eligible'
        END AS margin_rank_eligibility_status

    FROM product_family_rollup
),

product_family_rankings AS (
    SELECT
        *,
        RANK() OVER (
            PARTITION BY channel
            ORDER BY revenue_with_accepted_cogs DESC
        ) AS revenue_rank_in_channel,
        RANK() OVER (
            PARTITION BY channel
            ORDER BY estimated_gross_profit_before_fees DESC
        ) AS gross_profit_rank_in_channel,
        RANK() OVER (
            PARTITION BY channel
            ORDER BY estimated_gross_margin_before_fees DESC
        ) AS raw_gross_margin_rank_in_channel,
        CASE
            WHEN is_margin_rank_eligible THEN
                RANK() OVER (
                    PARTITION BY channel, is_margin_rank_eligible
                    ORDER BY estimated_gross_margin_before_fees DESC
                )
        END AS qualified_gross_margin_rank_in_channel
    FROM product_family_metrics
)

SELECT
    channel,
    product_family_name,
    source_product_family_key_count,
    source_product_family_keys,
    order_item_rows,
    order_count,
    units_sold,
    ROUND(gross_item_revenue, 2) AS gross_item_revenue,
    ROUND(net_item_revenue_before_refunds, 2) AS net_item_revenue_before_refunds,
    ROUND(revenue_with_accepted_cogs, 2) AS revenue_with_accepted_cogs,
    ROUND(revenue_without_accepted_cogs, 2) AS revenue_without_accepted_cogs,
    ROUND(
        revenue_excluded_from_profit_model,
        2
    ) AS revenue_excluded_from_profit_model,
    ROUND(estimated_item_cogs, 2) AS estimated_item_cogs,
    ROUND(
        estimated_gross_profit_before_fees,
        2
    ) AS estimated_gross_profit_before_fees,
    ROUND(
        estimated_gross_margin_before_fees,
        4
    ) AS estimated_gross_margin_before_fees,
    ROUND(
        accepted_cogs_revenue_coverage,
        4
    ) AS accepted_cogs_revenue_coverage,
    profitability_coverage_status,
    is_margin_rank_eligible,
    margin_rank_eligibility_status,
    revenue_rank_in_channel,
    gross_profit_rank_in_channel,
    raw_gross_margin_rank_in_channel,
    qualified_gross_margin_rank_in_channel
FROM product_family_rankings;
