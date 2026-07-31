-- sql/validation/product_profitability_mvp_validation.sql
-- Purpose:
-- Validate the Milestone 52 Product & Channel Profitability MVP contracts.
--
-- Semantic boundary:
-- - Profitability metrics are estimated gross product profitability before
--   channel fees, ad spend, shipping, labor, overhead, and payout
--   reconciliation.
-- - Historical COGS coverage is partial by design, so this script validates
--   model contracts rather than imposing arbitrary coverage thresholds.

WITH profitability_kpi_summary AS (
    SELECT *
    FROM `mischief-made-analytics.marts.anl_profitability_kpi_summary`
),

product_profitability_rankings AS (
    SELECT *
    FROM `mischief-made-analytics.marts.anl_product_profitability_rankings`
),

channel_profitability_monthly AS (
    SELECT *
    FROM `mischief-made-analytics.marts.anl_channel_profitability_monthly`
),

product_profitability_coverage_audit AS (
    SELECT *
    FROM `mischief-made-analytics.marts.anl_product_profitability_coverage_audit`
),

cross_channel_order_items AS (
    SELECT *
    FROM `mischief-made-analytics.marts.fct_cross_channel_order_items`
),

expected_period_boundaries AS (
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

kpi_summary_duplicates AS (
    SELECT
        order_month,
        channel,
        COUNT(*) AS row_count
    FROM profitability_kpi_summary
    GROUP BY
        order_month,
        channel
    HAVING COUNT(*) > 1
),

rankings_duplicates AS (
    SELECT
        channel,
        product_family_name,
        COUNT(*) AS row_count
    FROM product_profitability_rankings
    GROUP BY
        channel,
        product_family_name
    HAVING COUNT(*) > 1
),

rankings_contract_issues AS (
    SELECT
        COUNTIF(is_margin_rank_eligible IS NULL) AS null_eligibility_flags,
        COUNTIF(
            is_margin_rank_eligible
                AND (
                    margin_rank_eligibility_status IS NULL
                    OR margin_rank_eligibility_status != 'eligible'
                )
        ) AS eligible_rows_with_wrong_status,
        COUNTIF(
            NOT is_margin_rank_eligible
                AND margin_rank_eligibility_status = 'eligible'
        ) AS ineligible_rows_with_eligible_status,
        COUNTIF(
            NOT is_margin_rank_eligible
                AND qualified_gross_margin_rank_in_channel IS NOT NULL
        ) AS ineligible_rows_with_rank,
        COUNTIF(
            is_margin_rank_eligible
                AND qualified_gross_margin_rank_in_channel IS NULL
        ) AS eligible_rows_without_rank
    FROM product_profitability_rankings
),

rankings_minimum_rank_issues AS (
    SELECT
        COUNT(*) AS issue_count
    FROM (
        SELECT
            channel
        FROM product_profitability_rankings
        WHERE is_margin_rank_eligible
        GROUP BY
            channel
        HAVING MIN(qualified_gross_margin_rank_in_channel) IS NULL
            OR MIN(qualified_gross_margin_rank_in_channel) != 1
    )
),

rankings_lineage_issues AS (
    SELECT
        COUNTIF(
            source_product_family_key_count
                != ARRAY_LENGTH(source_product_family_keys)
            OR source_product_family_key_count IS NULL
            OR source_product_family_keys IS NULL
        ) AS key_count_mismatches,
        COUNTIF(
            EXISTS (
                SELECT 1
                FROM UNNEST(
                    COALESCE(
                        source_product_family_keys,
                        ARRAY<STRING>[]
                    )
                ) AS source_key
                WHERE source_key IS NULL
            )
        ) AS rows_with_null_array_elements
    FROM product_profitability_rankings
),

monthly_duplicates AS (
    SELECT
        order_month,
        channel,
        COUNT(*) AS row_count
    FROM channel_profitability_monthly
    GROUP BY
        order_month,
        channel
    HAVING COUNT(*) > 1
),

monthly_key_mismatches AS (
    SELECT COUNT(*) AS issue_count
    FROM profitability_kpi_summary AS source
    FULL OUTER JOIN channel_profitability_monthly AS monthly
        USING (order_month, channel)
    WHERE source.order_month IS NULL
        OR monthly.order_month IS NULL
),

monthly_preservation_issues AS (
    SELECT
        COUNTIF(
            ABS(source.net_item_revenue_before_refunds
                - monthly.net_item_revenue_before_refunds) > 0.01
            OR (source.net_item_revenue_before_refunds IS NULL)
                != (monthly.net_item_revenue_before_refunds IS NULL)
        ) AS revenue_mismatches,
        COUNTIF(
            ABS(source.revenue_with_accepted_cogs
                - monthly.revenue_with_accepted_cogs) > 0.01
            OR (source.revenue_with_accepted_cogs IS NULL)
                != (monthly.revenue_with_accepted_cogs IS NULL)
        ) AS accepted_revenue_mismatches,
        COUNTIF(
            ABS(source.estimated_item_cogs
                - monthly.estimated_item_cogs) > 0.01
            OR (source.estimated_item_cogs IS NULL)
                != (monthly.estimated_item_cogs IS NULL)
        ) AS cogs_mismatches,
        COUNTIF(
            ABS(source.estimated_gross_profit_before_fees
                - monthly.estimated_gross_profit_before_fees) > 0.01
            OR (source.estimated_gross_profit_before_fees IS NULL)
                != (monthly.estimated_gross_profit_before_fees IS NULL)
        ) AS gross_profit_mismatches,
        COUNTIF(
            ABS(source.estimated_gross_margin_before_fees
                - monthly.estimated_gross_margin_before_fees) > 0.0001
            OR (source.estimated_gross_margin_before_fees IS NULL)
                != (monthly.estimated_gross_margin_before_fees IS NULL)
        ) AS gross_margin_mismatches,
        COUNTIF(
            ABS(source.accepted_cogs_revenue_coverage
                - monthly.accepted_cogs_revenue_coverage) > 0.0001
            OR (source.accepted_cogs_revenue_coverage IS NULL)
                != (monthly.accepted_cogs_revenue_coverage IS NULL)
        ) AS coverage_mismatches,
        COUNTIF(
            NOT COALESCE(
                source.profitability_coverage_status
                    = monthly.profitability_coverage_status,
                source.profitability_coverage_status IS NULL
                    AND monthly.profitability_coverage_status IS NULL
            )
        ) AS coverage_status_mismatches
    FROM profitability_kpi_summary AS source
    INNER JOIN channel_profitability_monthly AS monthly
        USING (order_month, channel)
),

monthly_flag_issues AS (
    SELECT
        COUNTIF(
            NOT COALESCE(
                is_consecutive_month_comparison
                    = COALESCE(
                        previous_order_month
                            = DATE_SUB(order_month, INTERVAL 1 MONTH),
                        FALSE
                    ),
                FALSE
            )
        ) AS consecutive_flag_mismatches,
        COUNTIF(
            NOT COALESCE(
                is_complete_month
                    = COALESCE(
                        order_month < DATE_TRUNC(
                            CURRENT_DATE('America/Los_Angeles'),
                            MONTH
                        ),
                        FALSE
                    ),
                FALSE
            )
        ) AS complete_month_flag_mismatches,
        COUNTIF(
            NOT COALESCE(
                is_month_over_month_comparison_eligible
                    = (
                        is_consecutive_month_comparison
                        AND is_complete_month
                    ),
                FALSE
            )
        ) AS eligibility_flag_mismatches,
        COUNTIF(
            NOT COALESCE(is_month_over_month_comparison_eligible, FALSE)
            AND (
                revenue_with_accepted_cogs_month_over_month_change IS NOT NULL
                OR revenue_with_accepted_cogs_month_over_month_change_pct
                    IS NOT NULL
                OR estimated_gross_profit_month_over_month_change IS NOT NULL
                OR estimated_gross_profit_month_over_month_change_pct
                    IS NOT NULL
                OR estimated_gross_margin_month_over_month_change IS NOT NULL
            )
        ) AS ineligible_rows_with_changes
    FROM channel_profitability_monthly
),

monthly_arithmetic_issues AS (
    SELECT
        COUNTIF(
            (
                revenue_with_accepted_cogs_month_over_month_change IS NULL
            ) != (
                revenue_with_accepted_cogs
                    - previous_available_month_revenue_with_accepted_cogs
                IS NULL
            )
            OR (
                revenue_with_accepted_cogs_month_over_month_change IS NOT NULL
                AND revenue_with_accepted_cogs
                    - previous_available_month_revenue_with_accepted_cogs
                    IS NOT NULL
                AND ABS(
                    revenue_with_accepted_cogs_month_over_month_change
                    - (
                        revenue_with_accepted_cogs
                        - previous_available_month_revenue_with_accepted_cogs
                    )
                ) > 0.01
            )
        ) AS revenue_absolute_mismatches,
        COUNTIF(
            (
                ABS(
                    revenue_with_accepted_cogs_month_over_month_change_pct
                    - SAFE_DIVIDE(
                        revenue_with_accepted_cogs
                            - previous_available_month_revenue_with_accepted_cogs,
                        previous_available_month_revenue_with_accepted_cogs
                    )
                ) > 0.0001
            )
            OR (
                revenue_with_accepted_cogs_month_over_month_change_pct IS NULL
            ) != (
                SAFE_DIVIDE(
                    revenue_with_accepted_cogs
                        - previous_available_month_revenue_with_accepted_cogs,
                    previous_available_month_revenue_with_accepted_cogs
                ) IS NULL
            )
        ) AS revenue_percentage_mismatches,
        COUNTIF(
            (
                estimated_gross_profit_month_over_month_change IS NULL
            ) != (
                estimated_gross_profit_before_fees
                    - previous_available_month_estimated_gross_profit_before_fees
                IS NULL
            )
            OR (
                estimated_gross_profit_month_over_month_change IS NOT NULL
                AND estimated_gross_profit_before_fees
                    - previous_available_month_estimated_gross_profit_before_fees
                    IS NOT NULL
                AND ABS(
                    estimated_gross_profit_month_over_month_change
                    - (
                        estimated_gross_profit_before_fees
                        - previous_available_month_estimated_gross_profit_before_fees
                    )
                ) > 0.01
            )
        ) AS gross_profit_absolute_mismatches,
        COUNTIF(
            (
                ABS(
                    estimated_gross_profit_month_over_month_change_pct
                    - SAFE_DIVIDE(
                        estimated_gross_profit_before_fees
                            - previous_available_month_estimated_gross_profit_before_fees,
                        previous_available_month_estimated_gross_profit_before_fees
                    )
                ) > 0.0001
            )
            OR (
                estimated_gross_profit_month_over_month_change_pct IS NULL
            ) != (
                SAFE_DIVIDE(
                    estimated_gross_profit_before_fees
                        - previous_available_month_estimated_gross_profit_before_fees,
                    previous_available_month_estimated_gross_profit_before_fees
                ) IS NULL
            )
        ) AS gross_profit_percentage_mismatches,
        COUNTIF(
            (
                estimated_gross_margin_month_over_month_change IS NULL
            ) != (
                estimated_gross_margin_before_fees
                    - previous_available_month_estimated_gross_margin_before_fees
                IS NULL
            )
            OR (
                estimated_gross_margin_month_over_month_change IS NOT NULL
                AND estimated_gross_margin_before_fees
                    - previous_available_month_estimated_gross_margin_before_fees
                    IS NOT NULL
                AND ABS(
                    estimated_gross_margin_month_over_month_change
                    - (
                        estimated_gross_margin_before_fees
                        - previous_available_month_estimated_gross_margin_before_fees
                    )
                ) > 0.0001
            )
        ) AS gross_margin_absolute_mismatches
    FROM channel_profitability_monthly
    WHERE is_month_over_month_comparison_eligible
),

coverage_duplicates AS (
    SELECT
        channel,
        product_family_name,
        COUNT(*) AS row_count
    FROM product_profitability_coverage_audit
    GROUP BY
        channel,
        product_family_name
    HAVING COUNT(*) > 1
),

coverage_boundary_issues AS (
    SELECT COUNT(*) AS issue_count
    FROM product_profitability_coverage_audit AS audit
    CROSS JOIN expected_period_boundaries AS expected
    WHERE audit.recent_period_start != expected.recent_period_start
        OR audit.recent_period_end != expected.recent_period_end
        OR audit.current_month_start != expected.current_month_start
        OR audit.recent_period_start IS NULL
        OR audit.recent_period_end IS NULL
        OR audit.current_month_start IS NULL
),

coverage_partition_issues AS (
    SELECT
        COUNTIF(
            NOT COALESCE(
                order_item_rows = (
                    rows_with_accepted_cogs
                    + rows_missing_cogs
                    + rows_missing_sku
                    + rows_with_cogs_review_conflict
                    + rows_excluded_from_profit_model
                    + rows_with_unrecognized_cogs_status
                ),
                FALSE
            )
        ) AS row_partition_mismatches,
        COUNTIF(
            NOT COALESCE(
                ABS(
                    net_item_revenue_before_refunds
                    - (
                        revenue_with_accepted_cogs
                        + revenue_missing_cogs
                        + revenue_missing_sku
                        + revenue_with_cogs_review_conflict
                        + revenue_excluded_from_profit_model
                        + revenue_with_unrecognized_cogs_status
                    )
                ) <= 0.05,
                FALSE
            )
        ) AS revenue_partition_mismatches
    FROM product_profitability_coverage_audit
),

coverage_expected_values AS (
    SELECT
        *,
        SAFE_DIVIDE(
            revenue_with_accepted_cogs,
            net_item_revenue_before_refunds
        ) AS expected_accepted_cogs_revenue_coverage,
        SAFE_DIVIDE(
            recent_revenue_with_accepted_cogs,
            recent_net_item_revenue_before_refunds
        ) AS expected_recent_accepted_cogs_revenue_coverage,
        SAFE_DIVIDE(
            historical_revenue_with_accepted_cogs,
            historical_net_item_revenue_before_refunds
        ) AS expected_historical_accepted_cogs_revenue_coverage
    FROM product_profitability_coverage_audit
),

coverage_ratio_issues AS (
    SELECT
        COUNTIF(
            (
                accepted_cogs_revenue_coverage IS NULL
            ) != (
                expected_accepted_cogs_revenue_coverage IS NULL
            )
            OR (
                accepted_cogs_revenue_coverage IS NOT NULL
                AND expected_accepted_cogs_revenue_coverage IS NOT NULL
                AND ABS(
                    accepted_cogs_revenue_coverage
                    - expected_accepted_cogs_revenue_coverage
                ) > 0.0001
            )
        ) AS all_time_coverage_mismatches,
        COUNTIF(
            (
                recent_accepted_cogs_revenue_coverage IS NULL
            ) != (
                expected_recent_accepted_cogs_revenue_coverage IS NULL
            )
            OR (
                recent_accepted_cogs_revenue_coverage IS NOT NULL
                AND expected_recent_accepted_cogs_revenue_coverage IS NOT NULL
                AND ABS(
                    recent_accepted_cogs_revenue_coverage
                    - expected_recent_accepted_cogs_revenue_coverage
                ) > 0.0001
            )
        ) AS recent_coverage_mismatches,
        COUNTIF(
            (
                historical_accepted_cogs_revenue_coverage IS NULL
            ) != (
                expected_historical_accepted_cogs_revenue_coverage IS NULL
            )
            OR (
                historical_accepted_cogs_revenue_coverage IS NOT NULL
                AND expected_historical_accepted_cogs_revenue_coverage
                    IS NOT NULL
                AND ABS(
                    historical_accepted_cogs_revenue_coverage
                    - expected_historical_accepted_cogs_revenue_coverage
                ) > 0.0001
            )
        ) AS historical_coverage_mismatches,
        COUNTIF(
            (
                recent_coverage_minus_historical_coverage IS NULL
            ) != (
                expected_recent_accepted_cogs_revenue_coverage
                    - expected_historical_accepted_cogs_revenue_coverage
                IS NULL
            )
            OR (
                recent_coverage_minus_historical_coverage IS NOT NULL
                AND expected_recent_accepted_cogs_revenue_coverage
                    - expected_historical_accepted_cogs_revenue_coverage
                    IS NOT NULL
                AND ABS(
                    recent_coverage_minus_historical_coverage
                    - (
                        expected_recent_accepted_cogs_revenue_coverage
                        - expected_historical_accepted_cogs_revenue_coverage
                    )
                ) > 0.0001
            )
        ) AS coverage_difference_mismatches
    FROM coverage_expected_values
),

coverage_status_issues AS (
    SELECT
        COUNTIF(
            NOT COALESCE(
                all_time_profitability_coverage_status = CASE
                    WHEN net_item_revenue_before_refunds <= 0
                        THEN 'nonpositive_revenue_base'
                    WHEN expected_accepted_cogs_revenue_coverage >= 0.90
                        THEN 'high_cogs_coverage'
                    WHEN expected_accepted_cogs_revenue_coverage >= 0.70
                        THEN 'good_cogs_coverage'
                    WHEN expected_accepted_cogs_revenue_coverage >= 0.50
                        THEN 'partial_cogs_coverage'
                    WHEN expected_accepted_cogs_revenue_coverage > 0
                        THEN 'limited_cogs_coverage'
                    ELSE 'no_cogs_coverage'
                END,
                FALSE
            )
        ) AS all_time_status_mismatches,
        COUNTIF(
            NOT COALESCE(
                recent_profitability_coverage_status = CASE
                    WHEN recent_order_item_rows = 0
                        THEN 'no_recent_activity'
                    WHEN recent_net_item_revenue_before_refunds <= 0
                        THEN 'nonpositive_revenue_base'
                    WHEN expected_recent_accepted_cogs_revenue_coverage >= 0.90
                        THEN 'high_cogs_coverage'
                    WHEN expected_recent_accepted_cogs_revenue_coverage >= 0.70
                        THEN 'good_cogs_coverage'
                    WHEN expected_recent_accepted_cogs_revenue_coverage >= 0.50
                        THEN 'partial_cogs_coverage'
                    WHEN expected_recent_accepted_cogs_revenue_coverage > 0
                        THEN 'limited_cogs_coverage'
                    ELSE 'no_cogs_coverage'
                END,
                FALSE
            )
        ) AS recent_status_mismatches
    FROM coverage_expected_values
),

coverage_flag_issues AS (
    SELECT
        COUNTIF(
            NOT COALESCE(
                has_missing_sku_issue = (rows_missing_sku > 0),
                FALSE
            )
        ) AS missing_sku_flag_mismatches,
        COUNTIF(
            NOT COALESCE(
                has_cogs_review_conflict
                    = (rows_with_cogs_review_conflict > 0),
                FALSE
            )
        ) AS review_conflict_flag_mismatches,
        COUNTIF(
            NOT COALESCE(
                has_unrecognized_cogs_status
                    = (rows_with_unrecognized_cogs_status > 0),
                FALSE
            )
        ) AS unrecognized_status_flag_mismatches
    FROM product_profitability_coverage_audit
),

fact_contract_issues AS (
    SELECT
        COUNTIF(
            cogs_resolution_status IS NULL
            OR cogs_resolution_status NOT IN (
                'accepted',
                'missing_cogs',
                'missing_sku',
                'review_conflict',
                'excluded_from_profit_model'
            )
        ) AS unexpected_cogs_status_rows,
        COUNTIF(
            (
                LOWER(COALESCE(product_family_name, '')) LIKE '%mystery box%'
                OR LOWER(COALESCE(product_family_name, '')) LIKE '%gift card%'
            )
            AND NOT (
                COALESCE(
                    cogs_resolution_status = 'excluded_from_profit_model',
                    FALSE
                )
                AND COALESCE(cogs_match_grain = 'manual_exclusion', FALSE)
                AND COALESCE(cogs_match_type = 'manual_exclusion', FALSE)
            )
        ) AS intentional_exclusion_contract_violations,
        COUNTIF(
            cogs_resolution_status = 'accepted'
            AND (
                estimated_item_cogs IS NULL
                OR estimated_gross_profit_before_fees IS NULL
            )
        ) AS accepted_rows_without_profitability_values
    FROM cross_channel_order_items
),

validation_results AS (
    SELECT
        'profitability_kpi_summary' AS check_area,
        'order_month_channel_grain' AS check_name,
        IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNT(*) AS STRING) AS observed_value,
        '0 duplicate order_month/channel groups' AS expected_value,
        'KPI summary should have at most one row per order month and channel.' AS notes
    FROM kpi_summary_duplicates

    UNION ALL

    SELECT
        'product_profitability_rankings',
        'channel_product_family_name_grain',
        IF(COUNT(*) = 0, 'PASS', 'FAIL'),
        CAST(COUNT(*) AS STRING),
        '0 duplicate channel/product_family_name groups',
        'Rankings should have at most one row per channel and exact product family name.'
    FROM rankings_duplicates

    UNION ALL

    SELECT
        'product_profitability_rankings',
        'margin_rank_eligibility_contract',
        IF(
            null_eligibility_flags
                + eligible_rows_with_wrong_status
                + ineligible_rows_with_eligible_status
                + ineligible_rows_with_rank
                + eligible_rows_without_rank = 0,
            'PASS',
            'FAIL'
        ),
        CONCAT(
            'null_flags=', null_eligibility_flags,
            '; eligible_wrong_status=', eligible_rows_with_wrong_status,
            '; ineligible_eligible_status=', ineligible_rows_with_eligible_status,
            '; ineligible_with_rank=', ineligible_rows_with_rank,
            '; eligible_without_rank=', eligible_rows_without_rank
        ),
        '0 issues across eligibility status and qualified-rank rules',
        'Eligibility flags, statuses, and qualified ranks must remain internally consistent.'
    FROM rankings_contract_issues

    UNION ALL

    SELECT
        'product_profitability_rankings',
        'qualified_ranks_begin_at_one',
        IF(issue_count = 0, 'PASS', 'FAIL'),
        CAST(issue_count AS STRING),
        '0 channels whose eligible ranks do not begin at 1',
        'Every channel with eligible rows should have a minimum qualified rank of 1.'
    FROM rankings_minimum_rank_issues

    UNION ALL

    SELECT
        'product_profitability_rankings',
        'source_product_family_key_lineage',
        IF(
            key_count_mismatches + rows_with_null_array_elements = 0,
            'PASS',
            'FAIL'
        ),
        CONCAT(
            'count_mismatches=', key_count_mismatches,
            '; rows_with_null_elements=', rows_with_null_array_elements
        ),
        '0 count mismatches and 0 rows with NULL array elements',
        'The source-key count must match the array length, and lineage arrays cannot contain NULL.'
    FROM rankings_lineage_issues

    UNION ALL

    SELECT
        'channel_profitability_monthly',
        'order_month_channel_grain',
        IF(COUNT(*) = 0, 'PASS', 'FAIL'),
        CAST(COUNT(*) AS STRING),
        '0 duplicate order_month/channel groups',
        'Monthly channel profitability should have at most one row per order month and channel.'
    FROM monthly_duplicates

    UNION ALL

    SELECT
        'channel_profitability_monthly',
        'kpi_summary_keys_preserved',
        IF(issue_count = 0, 'PASS', 'FAIL'),
        CAST(issue_count AS STRING),
        '0 source or target keys missing',
        'Monthly channel keys should exactly match the KPI summary keys.'
    FROM monthly_key_mismatches

    UNION ALL

    SELECT
        'channel_profitability_monthly',
        'kpi_summary_metrics_preserved',
        IF(
            revenue_mismatches
                + accepted_revenue_mismatches
                + cogs_mismatches
                + gross_profit_mismatches
                + gross_margin_mismatches
                + coverage_mismatches
                + coverage_status_mismatches = 0,
            'PASS',
            'FAIL'
        ),
        CONCAT(
            'revenue=', revenue_mismatches,
            '; accepted_revenue=', accepted_revenue_mismatches,
            '; cogs=', cogs_mismatches,
            '; gross_profit=', gross_profit_mismatches,
            '; gross_margin=', gross_margin_mismatches,
            '; coverage=', coverage_mismatches,
            '; coverage_status=', coverage_status_mismatches
        ),
        '0 preserved KPI metric mismatches',
        'Money uses a 0.01 tolerance, ratios use 0.0001, and status matches exactly.'
    FROM monthly_preservation_issues

    UNION ALL

    SELECT
        'channel_profitability_monthly',
        'month_over_month_flags',
        IF(
            consecutive_flag_mismatches
                + complete_month_flag_mismatches
                + eligibility_flag_mismatches
                + ineligible_rows_with_changes = 0,
            'PASS',
            'FAIL'
        ),
        CONCAT(
            'consecutive=', consecutive_flag_mismatches,
            '; complete_month=', complete_month_flag_mismatches,
            '; eligibility=', eligibility_flag_mismatches,
            '; ineligible_with_changes=', ineligible_rows_with_changes
        ),
        '0 flag mismatches and 0 ineligible rows with change values',
        'Comparison flags must follow calendar-month rules, and ineligible changes must be NULL.'
    FROM monthly_flag_issues

    UNION ALL

    SELECT
        'channel_profitability_monthly',
        'month_over_month_arithmetic',
        IF(
            revenue_absolute_mismatches
                + revenue_percentage_mismatches
                + gross_profit_absolute_mismatches
                + gross_profit_percentage_mismatches
                + gross_margin_absolute_mismatches = 0,
            'PASS',
            'FAIL'
        ),
        CONCAT(
            'revenue_abs=', revenue_absolute_mismatches,
            '; revenue_pct=', revenue_percentage_mismatches,
            '; gross_profit_abs=', gross_profit_absolute_mismatches,
            '; gross_profit_pct=', gross_profit_percentage_mismatches,
            '; gross_margin_abs=', gross_margin_absolute_mismatches
        ),
        '0 eligible-row arithmetic mismatches',
        'Money uses a 0.01 tolerance and ratios use 0.0001; margin change is an absolute ratio difference.'
    FROM monthly_arithmetic_issues

    UNION ALL

    SELECT
        'product_profitability_coverage_audit',
        'channel_product_family_name_grain',
        IF(COUNT(*) = 0, 'PASS', 'FAIL'),
        CAST(COUNT(*) AS STRING),
        '0 duplicate channel/product_family_name groups',
        'Coverage audit should have at most one row per channel and exact product family name.'
    FROM coverage_duplicates

    UNION ALL

    SELECT
        'product_profitability_coverage_audit',
        'reporting_period_boundaries',
        IF(issue_count = 0, 'PASS', 'FAIL'),
        CAST(issue_count AS STRING),
        '0 rows with incorrect America/Los_Angeles boundaries',
        'The recent period is the 12 completed calendar months before the current month.'
    FROM coverage_boundary_issues

    UNION ALL

    SELECT
        'product_profitability_coverage_audit',
        'coverage_status_partitions',
        IF(
            row_partition_mismatches + revenue_partition_mismatches = 0,
            'PASS',
            'FAIL'
        ),
        CONCAT(
            'row_partitions=', row_partition_mismatches,
            '; revenue_partitions=', revenue_partition_mismatches
        ),
        '0 row or revenue partition mismatches',
        'Status buckets must fully reconcile rows and revenue; revenue tolerance is 0.05.'
    FROM coverage_partition_issues

    UNION ALL

    SELECT
        'product_profitability_coverage_audit',
        'coverage_ratio_arithmetic',
        IF(
            all_time_coverage_mismatches
                + recent_coverage_mismatches
                + historical_coverage_mismatches
                + coverage_difference_mismatches = 0,
            'PASS',
            'FAIL'
        ),
        CONCAT(
            'all_time=', all_time_coverage_mismatches,
            '; recent=', recent_coverage_mismatches,
            '; historical=', historical_coverage_mismatches,
            '; recent_minus_historical=', coverage_difference_mismatches
        ),
        '0 coverage-ratio arithmetic mismatches',
        'Coverage ratios and the recent-minus-historical difference must reconcile within 0.0001 with null-safe comparison.'
    FROM coverage_ratio_issues

    UNION ALL

    SELECT
        'product_profitability_coverage_audit',
        'coverage_status_logic',
        IF(
            all_time_status_mismatches + recent_status_mismatches = 0,
            'PASS',
            'FAIL'
        ),
        CONCAT(
            'all_time=', all_time_status_mismatches,
            '; recent=', recent_status_mismatches
        ),
        '0 all-time or recent coverage-status mismatches',
        'Coverage statuses must follow the contracted activity, revenue-base, and coverage-threshold logic.'
    FROM coverage_status_issues

    UNION ALL

    SELECT
        'product_profitability_coverage_audit',
        'issue_flags',
        IF(
            missing_sku_flag_mismatches
                + review_conflict_flag_mismatches
                + unrecognized_status_flag_mismatches = 0,
            'PASS',
            'FAIL'
        ),
        CONCAT(
            'missing_sku=', missing_sku_flag_mismatches,
            '; review_conflict=', review_conflict_flag_mismatches,
            '; unrecognized_status=', unrecognized_status_flag_mismatches
        ),
        '0 issue-flag mismatches',
        'Each issue flag must exactly represent whether its corresponding row count is positive.'
    FROM coverage_flag_issues

    UNION ALL

    SELECT
        'fct_cross_channel_order_items',
        'recognized_cogs_resolution_status',
        IF(unexpected_cogs_status_rows = 0, 'PASS', 'FAIL'),
        CAST(unexpected_cogs_status_rows AS STRING),
        '0 rows with NULL or unrecognized COGS status',
        'COGS resolution status must be one of the five modeled status values.'
    FROM fact_contract_issues

    UNION ALL

    SELECT
        'fct_cross_channel_order_items',
        'intentional_exclusion_classification',
        IF(intentional_exclusion_contract_violations = 0, 'PASS', 'FAIL'),
        CAST(intentional_exclusion_contract_violations AS STRING),
        '0 mystery box or gift card rows outside the exact manual-exclusion contract',
        'Intentional exclusions require excluded status, manual-exclusion match grain, and manual-exclusion match type.'
    FROM fact_contract_issues

    UNION ALL

    SELECT
        'fct_cross_channel_order_items',
        'accepted_cogs_profitability_values',
        IF(accepted_rows_without_profitability_values = 0, 'PASS', 'FAIL'),
        CAST(accepted_rows_without_profitability_values AS STRING),
        '0 accepted-COGS rows with missing estimated values',
        'Accepted-COGS rows require estimated item COGS and estimated gross profit before fees.'
    FROM fact_contract_issues
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
        WHEN 'PASS' THEN 2
        ELSE 3
    END,
    check_area,
    check_name;
