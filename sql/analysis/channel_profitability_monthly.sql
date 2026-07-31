-- sql/analysis/channel_profitability_monthly.sql
-- View: marts.anl_channel_profitability_monthly
-- Grain:
-- One row per order month and channel.
--
-- Purpose:
-- Provide monthly channel profitability trends and conservative
-- month-over-month comparisons.
--
-- Semantic boundaries:
-- - Profitability metrics are estimated gross product profitability before
--   fees, not net profit.
-- - Ad spend, fees, shipping, labor, and overhead are not included.
-- - Month-over-month changes are only calculated for consecutive calendar
--   months within the same channel when the current month is complete.
-- - Gross-margin change is an absolute difference between margin ratios. A
--   value of 0.05 represents a five-percentage-point increase when formatted
--   as a percentage; it is not a relative 5% change.
-- - The source view is already at the required grain and is not reaggregated.

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_channel_profitability_monthly` AS

WITH monthly_with_previous_values AS (
    SELECT
        order_month,
        channel,
        net_item_revenue_before_refunds,
        revenue_with_accepted_cogs,
        estimated_item_cogs,
        estimated_gross_profit_before_fees,
        estimated_gross_margin_before_fees,
        accepted_cogs_revenue_coverage,
        profitability_coverage_status,

        LAG(order_month) OVER (
            PARTITION BY channel
            ORDER BY order_month
        ) AS previous_order_month,
        LAG(revenue_with_accepted_cogs) OVER (
            PARTITION BY channel
            ORDER BY order_month
        ) AS previous_available_month_revenue_with_accepted_cogs,
        LAG(estimated_gross_profit_before_fees) OVER (
            PARTITION BY channel
            ORDER BY order_month
        ) AS previous_available_month_estimated_gross_profit_before_fees,
        LAG(estimated_gross_margin_before_fees) OVER (
            PARTITION BY channel
            ORDER BY order_month
        ) AS previous_available_month_estimated_gross_margin_before_fees

    FROM `mischief-made-analytics.marts.anl_profitability_kpi_summary`
),

monthly_with_comparison_flag AS (
    SELECT
        order_month,
        channel,
        net_item_revenue_before_refunds,
        revenue_with_accepted_cogs,
        estimated_item_cogs,
        estimated_gross_profit_before_fees,
        estimated_gross_margin_before_fees,
        accepted_cogs_revenue_coverage,
        profitability_coverage_status,
        previous_order_month,
        previous_available_month_revenue_with_accepted_cogs,
        previous_available_month_estimated_gross_profit_before_fees,
        previous_available_month_estimated_gross_margin_before_fees,
        COALESCE(
            previous_order_month = DATE_SUB(order_month, INTERVAL 1 MONTH),
            FALSE
        ) AS is_consecutive_month_comparison,
        COALESCE(
            order_month < DATE_TRUNC(
                CURRENT_DATE('America/Los_Angeles'),
                MONTH
            ),
            FALSE
        ) AS is_complete_month
    FROM monthly_with_previous_values
),

monthly_with_comparison_eligibility AS (
    SELECT
        order_month,
        channel,
        net_item_revenue_before_refunds,
        revenue_with_accepted_cogs,
        estimated_item_cogs,
        estimated_gross_profit_before_fees,
        estimated_gross_margin_before_fees,
        accepted_cogs_revenue_coverage,
        profitability_coverage_status,
        previous_order_month,
        previous_available_month_revenue_with_accepted_cogs,
        previous_available_month_estimated_gross_profit_before_fees,
        previous_available_month_estimated_gross_margin_before_fees,
        is_consecutive_month_comparison,
        is_complete_month,
        COALESCE(
            is_consecutive_month_comparison
                AND is_complete_month,
            FALSE
        ) AS is_month_over_month_comparison_eligible
    FROM monthly_with_comparison_flag
),

monthly_comparisons AS (
    SELECT
        order_month,
        channel,
        net_item_revenue_before_refunds,
        revenue_with_accepted_cogs,
        estimated_item_cogs,
        estimated_gross_profit_before_fees,
        estimated_gross_margin_before_fees,
        accepted_cogs_revenue_coverage,
        profitability_coverage_status,
        previous_order_month,
        previous_available_month_revenue_with_accepted_cogs,
        previous_available_month_estimated_gross_profit_before_fees,
        previous_available_month_estimated_gross_margin_before_fees,
        is_consecutive_month_comparison,
        is_complete_month,
        is_month_over_month_comparison_eligible,

        IF(
            is_month_over_month_comparison_eligible,
            revenue_with_accepted_cogs
                - previous_available_month_revenue_with_accepted_cogs,
            NULL
        ) AS revenue_with_accepted_cogs_month_over_month_change,

        IF(
            is_month_over_month_comparison_eligible,
            SAFE_DIVIDE(
                revenue_with_accepted_cogs
                    - previous_available_month_revenue_with_accepted_cogs,
                previous_available_month_revenue_with_accepted_cogs
            ),
            NULL
        ) AS revenue_with_accepted_cogs_month_over_month_change_pct,

        IF(
            is_month_over_month_comparison_eligible,
            estimated_gross_profit_before_fees
                - previous_available_month_estimated_gross_profit_before_fees,
            NULL
        ) AS estimated_gross_profit_month_over_month_change,

        IF(
            is_month_over_month_comparison_eligible,
            SAFE_DIVIDE(
                estimated_gross_profit_before_fees
                    - previous_available_month_estimated_gross_profit_before_fees,
                previous_available_month_estimated_gross_profit_before_fees
            ),
            NULL
        ) AS estimated_gross_profit_month_over_month_change_pct,

        IF(
            is_month_over_month_comparison_eligible,
            estimated_gross_margin_before_fees
                - previous_available_month_estimated_gross_margin_before_fees,
            NULL
        ) AS estimated_gross_margin_month_over_month_change

    FROM monthly_with_comparison_eligibility
)

SELECT
    order_month,
    channel,
    ROUND(net_item_revenue_before_refunds, 2) AS net_item_revenue_before_refunds,
    ROUND(revenue_with_accepted_cogs, 2) AS revenue_with_accepted_cogs,
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
    previous_order_month,
    ROUND(
        previous_available_month_revenue_with_accepted_cogs,
        2
    ) AS previous_available_month_revenue_with_accepted_cogs,
    ROUND(
        previous_available_month_estimated_gross_profit_before_fees,
        2
    ) AS previous_available_month_estimated_gross_profit_before_fees,
    ROUND(
        previous_available_month_estimated_gross_margin_before_fees,
        4
    ) AS previous_available_month_estimated_gross_margin_before_fees,
    is_consecutive_month_comparison,
    is_complete_month,
    is_month_over_month_comparison_eligible,
    ROUND(
        revenue_with_accepted_cogs_month_over_month_change,
        2
    ) AS revenue_with_accepted_cogs_month_over_month_change,
    ROUND(
        revenue_with_accepted_cogs_month_over_month_change_pct,
        4
    ) AS revenue_with_accepted_cogs_month_over_month_change_pct,
    ROUND(
        estimated_gross_profit_month_over_month_change,
        2
    ) AS estimated_gross_profit_month_over_month_change,
    ROUND(
        estimated_gross_profit_month_over_month_change_pct,
        4
    ) AS estimated_gross_profit_month_over_month_change_pct,
    ROUND(
        estimated_gross_margin_month_over_month_change,
        4
    ) AS estimated_gross_margin_month_over_month_change
FROM monthly_comparisons;
