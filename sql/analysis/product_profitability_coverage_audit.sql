-- sql/analysis/product_profitability_coverage_audit.sql
-- View: marts.anl_product_profitability_coverage_audit
-- Grain:
-- One row per channel and exact product family name.
--
-- Purpose:
-- Provide an auditable product-family view of accepted, missing, conflicting,
-- and manually excluded COGS coverage, comparing recent completed months with
-- older historical data.
--
-- Semantic boundaries:
-- - This view is limited to COGS coverage and data quality.
-- - The recent period is the 12 completed calendar months immediately before
--   the current month in the America/Los_Angeles timezone.
-- - Historical data contains rows earlier than the recent-period start.
-- - Current-month and missing-date rows remain visible in all-time metrics but
--   are not classified as recent completed-month or historical data.
-- - Source product-family keys are consolidated for reporting only; this view
--   does not alter source keys or force cross-channel identity matches.
-- - Manual exclusions remain distinct from missing COGS.
-- - Ratios are calculated after aggregation.

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_product_profitability_coverage_audit` AS

WITH period_boundaries AS (
    SELECT
        DATE_TRUNC(
            CURRENT_DATE('America/Los_Angeles'),
            MONTH
        ) AS current_month_start,
        DATE_SUB(
            DATE_TRUNC(
                CURRENT_DATE('America/Los_Angeles'),
                MONTH
            ),
            INTERVAL 12 MONTH
        ) AS recent_period_start,
        DATE_SUB(
            DATE_TRUNC(
                CURRENT_DATE('America/Los_Angeles'),
                MONTH
            ),
            INTERVAL 1 DAY
        ) AS recent_period_end
),

product_family_rollup AS (
    SELECT
        items.channel,
        COALESCE(
            items.product_family_name,
            'Unknown Product Family'
        ) AS product_family_name,
        ANY_VALUE(boundaries.recent_period_start) AS recent_period_start,
        ANY_VALUE(boundaries.recent_period_end) AS recent_period_end,
        ANY_VALUE(boundaries.current_month_start) AS current_month_start,

        COUNT(
            DISTINCT COALESCE(
                items.product_family_key,
                'unknown_product_family'
            )
        ) AS source_product_family_key_count,
        ARRAY_AGG(
            DISTINCT COALESCE(
                items.product_family_key,
                'unknown_product_family'
            )
            ORDER BY COALESCE(
                items.product_family_key,
                'unknown_product_family'
            )
        ) AS source_product_family_keys,

        COUNT(*) AS order_item_rows,
        SUM(items.net_item_revenue_before_refunds)
            AS net_item_revenue_before_refunds,

        COUNTIF(items.cogs_resolution_status = 'accepted')
            AS rows_with_accepted_cogs,
        COUNTIF(items.cogs_resolution_status = 'missing_cogs')
            AS rows_missing_cogs,
        COUNTIF(items.cogs_resolution_status = 'missing_sku')
            AS rows_missing_sku,
        COUNTIF(items.cogs_resolution_status = 'review_conflict')
            AS rows_with_cogs_review_conflict,
        COUNTIF(items.cogs_resolution_status = 'excluded_from_profit_model')
            AS rows_excluded_from_profit_model,
        COUNTIF(
            items.cogs_resolution_status IS NULL
                OR items.cogs_resolution_status NOT IN (
                    'accepted',
                    'missing_cogs',
                    'missing_sku',
                    'review_conflict',
                    'excluded_from_profit_model'
                )
        ) AS rows_with_unrecognized_cogs_status,

        SUM(
            IF(
                items.cogs_resolution_status = 'accepted',
                items.net_item_revenue_before_refunds,
                0
            )
        ) AS revenue_with_accepted_cogs,
        SUM(
            IF(
                items.cogs_resolution_status = 'missing_cogs',
                items.net_item_revenue_before_refunds,
                0
            )
        ) AS revenue_missing_cogs,
        SUM(
            IF(
                items.cogs_resolution_status = 'missing_sku',
                items.net_item_revenue_before_refunds,
                0
            )
        ) AS revenue_missing_sku,
        SUM(
            IF(
                items.cogs_resolution_status = 'review_conflict',
                items.net_item_revenue_before_refunds,
                0
            )
        ) AS revenue_with_cogs_review_conflict,
        SUM(
            IF(
                items.cogs_resolution_status = 'excluded_from_profit_model',
                items.net_item_revenue_before_refunds,
                0
            )
        ) AS revenue_excluded_from_profit_model,
        SUM(
            IF(
                items.cogs_resolution_status IS NULL
                    OR items.cogs_resolution_status NOT IN (
                        'accepted',
                        'missing_cogs',
                        'missing_sku',
                        'review_conflict',
                        'excluded_from_profit_model'
                    ),
                items.net_item_revenue_before_refunds,
                0
            )
        ) AS revenue_with_unrecognized_cogs_status,

        COUNTIF(
            items.order_date >= boundaries.recent_period_start
                AND items.order_date < boundaries.current_month_start
        ) AS recent_order_item_rows,

        SUM(
            IF(
                items.order_date >= boundaries.recent_period_start
                    AND items.order_date < boundaries.current_month_start,
                items.net_item_revenue_before_refunds,
                0
            )
        ) AS recent_net_item_revenue_before_refunds,
        SUM(
            IF(
                items.order_date >= boundaries.recent_period_start
                    AND items.order_date < boundaries.current_month_start
                    AND items.cogs_resolution_status = 'accepted',
                items.net_item_revenue_before_refunds,
                0
            )
        ) AS recent_revenue_with_accepted_cogs,
        SUM(
            IF(
                items.order_date >= boundaries.recent_period_start
                    AND items.order_date < boundaries.current_month_start
                    AND (
                        items.cogs_resolution_status IS NULL
                        OR items.cogs_resolution_status != 'accepted'
                    ),
                items.net_item_revenue_before_refunds,
                0
            )
        ) AS recent_revenue_without_accepted_cogs,

        COUNTIF(
            items.order_date < boundaries.recent_period_start
        ) AS historical_order_item_rows,

        SUM(
            IF(
                items.order_date < boundaries.recent_period_start,
                items.net_item_revenue_before_refunds,
                0
            )
        ) AS historical_net_item_revenue_before_refunds,
        SUM(
            IF(
                items.order_date < boundaries.recent_period_start
                    AND items.cogs_resolution_status = 'accepted',
                items.net_item_revenue_before_refunds,
                0
            )
        ) AS historical_revenue_with_accepted_cogs,
        SUM(
            IF(
                items.order_date < boundaries.recent_period_start
                    AND (
                        items.cogs_resolution_status IS NULL
                        OR items.cogs_resolution_status != 'accepted'
                    ),
                items.net_item_revenue_before_refunds,
                0
            )
        ) AS historical_revenue_without_accepted_cogs

    FROM `mischief-made-analytics.marts.fct_cross_channel_order_items` AS items
    CROSS JOIN period_boundaries AS boundaries
    GROUP BY
        items.channel,
        COALESCE(
            items.product_family_name,
            'Unknown Product Family'
        )
),

coverage_metrics AS (
    SELECT
        channel,
        product_family_name,
        recent_period_start,
        recent_period_end,
        current_month_start,
        source_product_family_key_count,
        source_product_family_keys,
        order_item_rows,
        net_item_revenue_before_refunds,
        rows_with_accepted_cogs,
        rows_missing_cogs,
        rows_missing_sku,
        rows_with_cogs_review_conflict,
        rows_excluded_from_profit_model,
        rows_with_unrecognized_cogs_status,
        revenue_with_accepted_cogs,
        revenue_missing_cogs,
        revenue_missing_sku,
        revenue_with_cogs_review_conflict,
        revenue_excluded_from_profit_model,
        revenue_with_unrecognized_cogs_status,
        recent_order_item_rows,
        recent_net_item_revenue_before_refunds,
        recent_revenue_with_accepted_cogs,
        recent_revenue_without_accepted_cogs,
        historical_order_item_rows,
        historical_net_item_revenue_before_refunds,
        historical_revenue_with_accepted_cogs,
        historical_revenue_without_accepted_cogs,

        SAFE_DIVIDE(
            revenue_with_accepted_cogs,
            net_item_revenue_before_refunds
        ) AS accepted_cogs_revenue_coverage,
        SAFE_DIVIDE(
            recent_revenue_with_accepted_cogs,
            recent_net_item_revenue_before_refunds
        ) AS recent_accepted_cogs_revenue_coverage,
        SAFE_DIVIDE(
            historical_revenue_with_accepted_cogs,
            historical_net_item_revenue_before_refunds
        ) AS historical_accepted_cogs_revenue_coverage,

        CASE
            WHEN net_item_revenue_before_refunds <= 0
                THEN 'nonpositive_revenue_base'
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
            WHEN SAFE_DIVIDE(
                revenue_with_accepted_cogs,
                net_item_revenue_before_refunds
            ) > 0
                THEN 'limited_cogs_coverage'
            ELSE 'no_cogs_coverage'
        END AS all_time_profitability_coverage_status,

        CASE
            WHEN recent_order_item_rows = 0
                THEN 'no_recent_activity'
            WHEN recent_net_item_revenue_before_refunds <= 0
                THEN 'nonpositive_revenue_base'
            WHEN SAFE_DIVIDE(
                recent_revenue_with_accepted_cogs,
                recent_net_item_revenue_before_refunds
            ) >= 0.90
                THEN 'high_cogs_coverage'
            WHEN SAFE_DIVIDE(
                recent_revenue_with_accepted_cogs,
                recent_net_item_revenue_before_refunds
            ) >= 0.70
                THEN 'good_cogs_coverage'
            WHEN SAFE_DIVIDE(
                recent_revenue_with_accepted_cogs,
                recent_net_item_revenue_before_refunds
            ) >= 0.50
                THEN 'partial_cogs_coverage'
            WHEN SAFE_DIVIDE(
                recent_revenue_with_accepted_cogs,
                recent_net_item_revenue_before_refunds
            ) > 0
                THEN 'limited_cogs_coverage'
            ELSE 'no_cogs_coverage'
        END AS recent_profitability_coverage_status,

        rows_missing_sku > 0 AS has_missing_sku_issue,
        rows_with_cogs_review_conflict > 0 AS has_cogs_review_conflict,
        rows_with_unrecognized_cogs_status > 0
            AS has_unrecognized_cogs_status

    FROM product_family_rollup
)

SELECT
    channel,
    product_family_name,
    recent_period_start,
    recent_period_end,
    current_month_start,
    source_product_family_key_count,
    source_product_family_keys,
    order_item_rows,
    ROUND(
        net_item_revenue_before_refunds,
        2
    ) AS net_item_revenue_before_refunds,
    rows_with_accepted_cogs,
    rows_missing_cogs,
    rows_missing_sku,
    rows_with_cogs_review_conflict,
    rows_excluded_from_profit_model,
    rows_with_unrecognized_cogs_status,
    ROUND(revenue_with_accepted_cogs, 2) AS revenue_with_accepted_cogs,
    ROUND(revenue_missing_cogs, 2) AS revenue_missing_cogs,
    ROUND(revenue_missing_sku, 2) AS revenue_missing_sku,
    ROUND(
        revenue_with_cogs_review_conflict,
        2
    ) AS revenue_with_cogs_review_conflict,
    ROUND(
        revenue_excluded_from_profit_model,
        2
    ) AS revenue_excluded_from_profit_model,
    ROUND(
        revenue_with_unrecognized_cogs_status,
        2
    ) AS revenue_with_unrecognized_cogs_status,
    ROUND(
        accepted_cogs_revenue_coverage,
        4
    ) AS accepted_cogs_revenue_coverage,
    recent_order_item_rows,
    ROUND(
        recent_net_item_revenue_before_refunds,
        2
    ) AS recent_net_item_revenue_before_refunds,
    ROUND(
        recent_revenue_with_accepted_cogs,
        2
    ) AS recent_revenue_with_accepted_cogs,
    ROUND(
        recent_revenue_without_accepted_cogs,
        2
    ) AS recent_revenue_without_accepted_cogs,
    ROUND(
        recent_accepted_cogs_revenue_coverage,
        4
    ) AS recent_accepted_cogs_revenue_coverage,
    historical_order_item_rows,
    ROUND(
        historical_net_item_revenue_before_refunds,
        2
    ) AS historical_net_item_revenue_before_refunds,
    ROUND(
        historical_revenue_with_accepted_cogs,
        2
    ) AS historical_revenue_with_accepted_cogs,
    ROUND(
        historical_revenue_without_accepted_cogs,
        2
    ) AS historical_revenue_without_accepted_cogs,
    ROUND(
        historical_accepted_cogs_revenue_coverage,
        4
    ) AS historical_accepted_cogs_revenue_coverage,
    ROUND(
        recent_accepted_cogs_revenue_coverage
            - historical_accepted_cogs_revenue_coverage,
        4
    ) AS recent_coverage_minus_historical_coverage,
    all_time_profitability_coverage_status,
    recent_profitability_coverage_status,
    has_missing_sku_issue,
    has_cogs_review_conflict,
    has_unrecognized_cogs_status
FROM coverage_metrics;
