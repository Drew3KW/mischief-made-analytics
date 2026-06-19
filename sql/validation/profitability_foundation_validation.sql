-- sql/validation/profitability_foundation_validation.sql
-- Purpose:
-- Validate Milestone 51 COGS and profitability foundation models.
--
-- Scope:
-- - raw_load.product_cogs_manual_latest
-- - raw_load.product_family_cogs_overrides_latest
-- - marts.product_cogs_map
-- - marts.product_family_cogs_map
-- - marts.product_name_type_cogs_map
-- - marts.product_family_cogs_override_map
-- - marts.fct_cross_channel_order_items
-- - marts.anl_product_profitability_summary
-- - marts.anl_product_profitability_monthly
--
-- Notes:
-- - Profit is estimated gross profit before channel fees, ad spend, shipping,
--   labor, overhead, and payout reconciliation.
-- - Historical COGS coverage is partial by design.
-- - Recent/current COGS coverage is expected to be materially stronger.
-- - INFO rows document coverage and known limitations.
-- - REVIEW rows are non-failing quality signals.

WITH raw_cogs AS (
    SELECT *
    FROM `mischief-made-analytics.raw_load.product_cogs_manual_latest`
),

raw_overrides AS (
    SELECT *
    FROM `mischief-made-analytics.raw_load.product_family_cogs_overrides_latest`
),

sku_cogs AS (
    SELECT *
    FROM `mischief-made-analytics.marts.product_cogs_map`
),

family_cogs AS (
    SELECT *
    FROM `mischief-made-analytics.marts.product_family_cogs_map`
),

name_type_cogs AS (
    SELECT *
    FROM `mischief-made-analytics.marts.product_name_type_cogs_map`
),

override_cogs AS (
    SELECT *
    FROM `mischief-made-analytics.marts.product_family_cogs_override_map`
),

cross_channel_items AS (
    SELECT *
    FROM `mischief-made-analytics.marts.fct_cross_channel_order_items`
),

profitability_summary AS (
    SELECT *
    FROM `mischief-made-analytics.marts.anl_product_profitability_summary`
),

profitability_monthly AS (
    SELECT *
    FROM `mischief-made-analytics.marts.anl_product_profitability_monthly`
),

source_item_counts AS (
    SELECT
        (
            SELECT COUNT(*)
            FROM `mischief-made-analytics.marts.fct_order_items`
        )
        +
        (
            SELECT COUNT(*)
            FROM `mischief-made-analytics.marts.fct_etsy_order_items`
        ) AS source_order_item_rows
),

cross_channel_item_key_duplicates AS (
    SELECT
        cross_channel_order_item_key,
        COUNT(*) AS row_count
    FROM cross_channel_items
    GROUP BY
        cross_channel_order_item_key
    HAVING COUNT(*) > 1
),

sku_cogs_key_duplicates AS (
    SELECT
        normalized_sku,
        COUNT(*) AS row_count
    FROM sku_cogs
    GROUP BY
        normalized_sku
    HAVING COUNT(*) > 1
),

family_cogs_key_duplicates AS (
    SELECT
        product_family_key,
        COUNT(*) AS row_count
    FROM family_cogs
    GROUP BY
        product_family_key
    HAVING COUNT(*) > 1
),

name_type_cogs_key_duplicates AS (
    SELECT
        product_design_name_key,
        product_type_group,
        COUNT(*) AS row_count
    FROM name_type_cogs
    GROUP BY
        product_design_name_key,
        product_type_group
    HAVING COUNT(*) > 1
),

override_cogs_key_duplicates AS (
    SELECT
        product_family_key,
        COUNT(*) AS row_count
    FROM override_cogs
    GROUP BY
        product_family_key
    HAVING COUNT(*) > 1
),

recent_channel_coverage AS (
    SELECT
        channel,
        ROUND(SUM(net_item_revenue_before_refunds), 2) AS recent_revenue,
        ROUND(
            SUM(
                IF(
                    cogs_resolution_status = 'accepted',
                    net_item_revenue_before_refunds,
                    0
                )
            ),
            2
        ) AS recent_revenue_with_accepted_cogs,
        SAFE_DIVIDE(
            SUM(
                IF(
                    cogs_resolution_status = 'accepted',
                    net_item_revenue_before_refunds,
                    0
                )
            ),
            SUM(net_item_revenue_before_refunds)
        ) AS recent_accepted_cogs_revenue_coverage
    FROM cross_channel_items
    WHERE order_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
    GROUP BY
        channel
),

all_time_channel_coverage AS (
    SELECT
        channel,
        ROUND(SUM(net_item_revenue_before_refunds), 2) AS all_time_revenue,
        ROUND(
            SUM(
                IF(
                    cogs_resolution_status = 'accepted',
                    net_item_revenue_before_refunds,
                    0
                )
            ),
            2
        ) AS all_time_revenue_with_accepted_cogs,
        SAFE_DIVIDE(
            SUM(
                IF(
                    cogs_resolution_status = 'accepted',
                    net_item_revenue_before_refunds,
                    0
                )
            ),
            SUM(net_item_revenue_before_refunds)
        ) AS all_time_accepted_cogs_revenue_coverage
    FROM cross_channel_items
    GROUP BY
        channel
),

validation_results AS (
    SELECT
        'raw_cogs' AS check_area,
        'raw_manual_cogs_loaded' AS check_name,
        IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNT(*) AS STRING) AS observed_value,
        'greater than 0 rows' AS expected_value,
        'Manual COGS source should be loaded into raw_load.' AS notes
    FROM raw_cogs

    UNION ALL

    SELECT
        'raw_cogs' AS check_area,
        'raw_manual_cogs_has_cost_values' AS check_name,
        IF(COUNTIF(has_unit_cogs) > 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNTIF(has_unit_cogs) AS STRING) AS observed_value,
        'greater than 0 rows with unit COGS' AS expected_value,
        'Manual COGS source should contain usable unit cost values.' AS notes
    FROM raw_cogs

    UNION ALL

    SELECT
        'raw_overrides' AS check_area,
        'raw_product_family_overrides_loaded' AS check_name,
        IF(COUNT(*) > 0, 'PASS', 'REVIEW') AS check_status,
        CAST(COUNT(*) AS STRING) AS observed_value,
        'greater than 0 rows if overrides are in use' AS expected_value,
        'Manual product-family override source should be loaded when override layer is active.' AS notes
    FROM raw_overrides

    UNION ALL

    SELECT
        'sku_cogs_map' AS check_area,
        'sku_cogs_map_key_unique' AS check_name,
        IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNT(*) AS STRING) AS observed_value,
        '0 duplicate normalized_sku rows' AS expected_value,
        'SKU COGS map should have one row per normalized SKU.' AS notes
    FROM sku_cogs_key_duplicates

    UNION ALL

    SELECT
        'sku_cogs_map' AS check_area,
        'usable_sku_cogs_have_unit_cogs' AS check_name,
        IF(
            COUNTIF(is_usable_for_profit_model AND unit_cogs IS NULL) = 0,
            'PASS',
            'FAIL'
        ) AS check_status,
        CAST(
            COUNTIF(is_usable_for_profit_model AND unit_cogs IS NULL)
            AS STRING
        ) AS observed_value,
        '0 usable SKU COGS rows without unit_cogs' AS expected_value,
        'Rows marked usable for profit modeling must have unit COGS.' AS notes
    FROM sku_cogs

    UNION ALL

    SELECT
        'family_cogs_map' AS check_area,
        'family_cogs_map_key_unique' AS check_name,
        IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNT(*) AS STRING) AS observed_value,
        '0 duplicate product_family_key rows' AS expected_value,
        'Product-family COGS map should have one row per product family.' AS notes
    FROM family_cogs_key_duplicates

    UNION ALL

    SELECT
        'family_cogs_map' AS check_area,
        'usable_family_cogs_have_unit_cogs' AS check_name,
        IF(
            COUNTIF(is_usable_for_profit_model AND unit_cogs IS NULL) = 0,
            'PASS',
            'FAIL'
        ) AS check_status,
        CAST(
            COUNTIF(is_usable_for_profit_model AND unit_cogs IS NULL)
            AS STRING
        ) AS observed_value,
        '0 usable family COGS rows without unit_cogs' AS expected_value,
        'Rows marked usable for profit modeling must have unit COGS.' AS notes
    FROM family_cogs

    UNION ALL

    SELECT
        'name_type_cogs_map' AS check_area,
        'name_type_cogs_map_key_unique' AS check_name,
        IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNT(*) AS STRING) AS observed_value,
        '0 duplicate product_design_name_key/product_type_group rows' AS expected_value,
        'Name/type COGS map should have one row per design-name and product-type pair.' AS notes
    FROM name_type_cogs_key_duplicates

    UNION ALL

    SELECT
        'name_type_cogs_map' AS check_area,
        'usable_name_type_cogs_have_unit_cogs' AS check_name,
        IF(
            COUNTIF(is_usable_for_profit_model AND unit_cogs IS NULL) = 0,
            'PASS',
            'FAIL'
        ) AS check_status,
        CAST(
            COUNTIF(is_usable_for_profit_model AND unit_cogs IS NULL)
            AS STRING
        ) AS observed_value,
        '0 usable name/type COGS rows without unit_cogs' AS expected_value,
        'Rows marked usable for profit modeling must have unit COGS.' AS notes
    FROM name_type_cogs

    UNION ALL

    SELECT
        'override_cogs_map' AS check_area,
        'override_cogs_map_key_unique' AS check_name,
        IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNT(*) AS STRING) AS observed_value,
        '0 duplicate product_family_key rows' AS expected_value,
        'Manual override COGS map should have one row per product family.' AS notes
    FROM override_cogs_key_duplicates

    UNION ALL

    SELECT
        'override_cogs_map' AS check_area,
        'override_cogs_no_conflict_or_invalid_rows' AS check_name,
        IF(
            COUNTIF(override_resolution_status IN ('override_conflict', 'invalid_override')) = 0,
            'PASS',
            'FAIL'
        ) AS check_status,
        CAST(
            COUNTIF(override_resolution_status IN ('override_conflict', 'invalid_override'))
            AS STRING
        ) AS observed_value,
        '0 override_conflict or invalid_override rows' AS expected_value,
        'Manual override layer should not contain conflicting or invalid override instructions.' AS notes
    FROM override_cogs

    UNION ALL

    SELECT
        'override_cogs_map' AS check_area,
        'accepted_overrides_have_unit_cogs' AS check_name,
        IF(
            COUNTIF(override_resolution_status = 'accepted_override' AND unit_cogs IS NULL) = 0,
            'PASS',
            'FAIL'
        ) AS check_status,
        CAST(
            COUNTIF(override_resolution_status = 'accepted_override' AND unit_cogs IS NULL)
            AS STRING
        ) AS observed_value,
        '0 accepted overrides without unit_cogs' AS expected_value,
        'Accepted manual overrides must have unit COGS.' AS notes
    FROM override_cogs

    UNION ALL

    SELECT
        'cross_channel_order_items' AS check_area,
        'cross_channel_order_item_key_unique' AS check_name,
        IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNT(*) AS STRING) AS observed_value,
        '0 duplicate cross_channel_order_item_key rows' AS expected_value,
        'Cross-channel item fact should have one row per channel order item key.' AS notes
    FROM cross_channel_item_key_duplicates

    UNION ALL

    SELECT
        'cross_channel_order_items' AS check_area,
        'cross_channel_order_items_tie_to_source_facts' AS check_name,
        IF(
            (SELECT COUNT(*) FROM cross_channel_items)
            =
            (SELECT source_order_item_rows FROM source_item_counts),
            'PASS',
            'FAIL'
        ) AS check_status,
        CAST((SELECT COUNT(*) FROM cross_channel_items) AS STRING) AS observed_value,
        CAST((SELECT source_order_item_rows FROM source_item_counts) AS STRING) AS expected_value,
        'Cross-channel item fact row count should equal Shopify item rows plus Etsy item rows.' AS notes

    UNION ALL

    SELECT
        'cross_channel_order_items' AS check_area,
        'accepted_cogs_rows_have_cost_and_profit_values' AS check_name,
        IF(
            COUNTIF(
                cogs_resolution_status = 'accepted'
                AND (
                    unit_cogs IS NULL
                    OR estimated_item_cogs IS NULL
                    OR estimated_gross_profit_before_fees IS NULL
                )
            ) = 0,
            'PASS',
            'FAIL'
        ) AS check_status,
        CAST(
            COUNTIF(
                cogs_resolution_status = 'accepted'
                AND (
                    unit_cogs IS NULL
                    OR estimated_item_cogs IS NULL
                    OR estimated_gross_profit_before_fees IS NULL
                )
            ) AS STRING
        ) AS observed_value,
        '0 accepted COGS rows missing unit/profit values' AS expected_value,
        'Accepted COGS rows should have estimated COGS and gross profit values.' AS notes
    FROM cross_channel_items

    UNION ALL

    SELECT
        'cross_channel_order_items' AS check_area,
        'expected_cogs_resolution_statuses' AS check_name,
        IF(
            COUNTIF(cogs_resolution_status NOT IN (
                'accepted',
                'missing_cogs',
                'missing_sku',
                'review_conflict',
                'excluded_from_profit_model'
            )) = 0,
            'PASS',
            'FAIL'
        ) AS check_status,
        CAST(
            COUNTIF(cogs_resolution_status NOT IN (
                'accepted',
                'missing_cogs',
                'missing_sku',
                'review_conflict',
                'excluded_from_profit_model'
            )) AS STRING
        ) AS observed_value,
        '0 unexpected COGS resolution statuses' AS expected_value,
        'COGS resolution statuses should stay within the approved values.' AS notes
    FROM cross_channel_items

    UNION ALL

    SELECT
        'profitability_views' AS check_area,
        'profitability_summary_has_rows' AS check_name,
        IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNT(*) AS STRING) AS observed_value,
        'greater than 0 rows' AS expected_value,
        'Product profitability summary view should return rows.' AS notes
    FROM profitability_summary

    UNION ALL

    SELECT
        'profitability_views' AS check_area,
        'profitability_monthly_has_rows' AS check_name,
        IF(COUNT(*) > 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNT(*) AS STRING) AS observed_value,
        'greater than 0 rows' AS expected_value,
        'Monthly product profitability view should return rows.' AS notes
    FROM profitability_monthly

    UNION ALL

    SELECT
        'profitability_views' AS check_area,
        'profitability_summary_revenue_ties_to_fact' AS check_name,
        IF(
            ABS(
                (SELECT ROUND(SUM(net_item_revenue_before_refunds), 2) FROM profitability_summary)
                -
                (SELECT ROUND(SUM(net_item_revenue_before_refunds), 2) FROM cross_channel_items)
            ) <= 0.01,
            'PASS',
            'FAIL'
        ) AS check_status,
        CAST((SELECT ROUND(SUM(net_item_revenue_before_refunds), 2) FROM profitability_summary) AS STRING) AS observed_value,
        CAST((SELECT ROUND(SUM(net_item_revenue_before_refunds), 2) FROM cross_channel_items) AS STRING) AS expected_value,
        'Profitability summary revenue should tie to cross-channel item fact revenue.' AS notes

    UNION ALL

    SELECT
        'profitability_views' AS check_area,
        'profitability_monthly_revenue_ties_to_fact' AS check_name,
        IF(
            ABS(
                (SELECT ROUND(SUM(net_item_revenue_before_refunds), 2) FROM profitability_monthly)
                -
                (
                    SELECT ROUND(SUM(net_item_revenue_before_refunds), 2)
                    FROM cross_channel_items
                    WHERE order_date IS NOT NULL
                )
            ) <= 0.01,
            'PASS',
            'FAIL'
        ) AS check_status,
        CAST((SELECT ROUND(SUM(net_item_revenue_before_refunds), 2) FROM profitability_monthly) AS STRING) AS observed_value,
        CAST((
            SELECT ROUND(SUM(net_item_revenue_before_refunds), 2)
            FROM cross_channel_items
            WHERE order_date IS NOT NULL
        ) AS STRING) AS expected_value,
        'Monthly profitability revenue should tie to dated cross-channel item fact revenue.' AS notes

    UNION ALL

    SELECT
        'coverage' AS check_area,
        CONCAT('recent_365_cogs_revenue_coverage_', channel) AS check_name,
        IF(
            recent_accepted_cogs_revenue_coverage >= 0.70,
            'PASS',
            'REVIEW'
        ) AS check_status,
        CAST(ROUND(recent_accepted_cogs_revenue_coverage, 4) AS STRING) AS observed_value,
        '>= 0.70 recent accepted COGS revenue coverage' AS expected_value,
        'Recent/current profitability should have materially useful COGS coverage. REVIEW is non-failing but should be monitored.' AS notes
    FROM recent_channel_coverage

    UNION ALL

    SELECT
        'coverage' AS check_area,
        CONCAT('all_time_cogs_revenue_coverage_', channel) AS check_name,
        'INFO' AS check_status,
        CAST(ROUND(all_time_accepted_cogs_revenue_coverage, 4) AS STRING) AS observed_value,
        'informational' AS expected_value,
        'All-time COGS coverage is informational because older historical products may not exist in the current COGS source.' AS notes
    FROM all_time_channel_coverage

    UNION ALL

    SELECT
        'coverage' AS check_area,
        'coverage_by_cogs_match_grain' AS check_name,
        'INFO' AS check_status,
        ARRAY_TO_STRING(
            ARRAY_AGG(
                CONCAT(
                    channel,
                    ':',
                    COALESCE(cogs_match_grain, 'none'),
                    '=',
                    CAST(ROUND(revenue_with_grain, 2) AS STRING)
                )
                ORDER BY channel, COALESCE(cogs_match_grain, 'none')
            ),
            '; '
        ) AS observed_value,
        'informational' AS expected_value,
        'Revenue covered by SKU, manual override, product-family, name/type, or missing COGS grain.' AS notes
    FROM (
        SELECT
            channel,
            cogs_match_grain,
            SUM(net_item_revenue_before_refunds) AS revenue_with_grain
        FROM cross_channel_items
        GROUP BY
            channel,
            cogs_match_grain
    )
)

SELECT
    check_area,
    check_name,
    check_status,
    observed_value,
    expected_value,
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
    check_area,
    check_name;