-- sql/marts/product_family_cogs_override_map.sql
-- Model: marts.product_family_cogs_override_map
-- Grain:
-- One row per product_family_key from the manual override source.
--
-- Purpose:
-- Create an explicit manual override layer for recent/current COGS gaps.
--
-- Notes:
-- - estimate_cogs rows provide manually estimated unit COGS.
-- - exclude_from_profit_model rows mark bundles, gift cards, or non-product
--   rows that should not be treated as missing product COGS.
-- - Conflicting override instructions remain visible and are not auto-accepted.

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.product_family_cogs_override_map` AS

WITH raw_overrides AS (
    SELECT
        source_file_name,
        source_row_number,
        loaded_at,
        normalized_product_family_key AS product_family_key,
        product_family_name,
        unit_cogs,
        override_action,
        override_reason,
        notes,
        is_estimate_cogs,
        is_exclude_from_profit_model,
        has_unit_cogs
    FROM `mischief-made-analytics.raw_load.product_family_cogs_overrides_latest`
    WHERE normalized_product_family_key IS NOT NULL
),

override_rollup AS (
    SELECT
        product_family_key,

        ARRAY_AGG(
            product_family_name IGNORE NULLS
            ORDER BY source_row_number
            LIMIT 1
        )[SAFE_OFFSET(0)] AS product_family_name,

        COUNT(*) AS override_row_count,
        COUNTIF(is_estimate_cogs) AS estimate_cogs_row_count,
        COUNTIF(is_exclude_from_profit_model) AS exclude_from_profit_model_row_count,

        COUNT(DISTINCT IF(is_estimate_cogs, unit_cogs, NULL)) AS distinct_estimated_unit_cogs_count,

        ARRAY_AGG(DISTINCT unit_cogs IGNORE NULLS ORDER BY unit_cogs LIMIT 10) AS unit_cogs_values,
        ARRAY_AGG(DISTINCT override_action IGNORE NULLS ORDER BY override_action LIMIT 10) AS override_actions,
        ARRAY_AGG(DISTINCT override_reason IGNORE NULLS ORDER BY override_reason LIMIT 10) AS override_reasons,
        ARRAY_AGG(DISTINCT notes IGNORE NULLS LIMIT 10) AS notes_examples,

        MIN(source_row_number) AS first_source_row_number,
        MAX(source_row_number) AS last_source_row_number,
        MAX(loaded_at) AS latest_loaded_at
    FROM raw_overrides
    GROUP BY
        product_family_key
)

SELECT
    product_family_key,
    product_family_name,

    CASE
        WHEN estimate_cogs_row_count > 0
          AND exclude_from_profit_model_row_count = 0
          AND distinct_estimated_unit_cogs_count = 1
            THEN unit_cogs_values[SAFE_OFFSET(0)]
        ELSE NULL
    END AS unit_cogs,

    CASE
        WHEN estimate_cogs_row_count > 0
          AND exclude_from_profit_model_row_count > 0
            THEN 'override_conflict'
        WHEN estimate_cogs_row_count > 0
          AND distinct_estimated_unit_cogs_count = 1
            THEN 'accepted_override'
        WHEN estimate_cogs_row_count > 0
          AND distinct_estimated_unit_cogs_count > 1
            THEN 'override_conflict'
        WHEN exclude_from_profit_model_row_count > 0
            THEN 'excluded_from_profit_model'
        ELSE 'invalid_override'
    END AS override_resolution_status,

    CASE
        WHEN estimate_cogs_row_count > 0
          AND exclude_from_profit_model_row_count = 0
          AND distinct_estimated_unit_cogs_count = 1
            THEN TRUE
        ELSE FALSE
    END AS is_usable_for_profit_model,

    CASE
        WHEN exclude_from_profit_model_row_count > 0
          AND estimate_cogs_row_count = 0
            THEN TRUE
        ELSE FALSE
    END AS is_excluded_from_profit_model,

    'manual_product_family_override' AS cogs_source,

    override_row_count,
    estimate_cogs_row_count,
    exclude_from_profit_model_row_count,
    distinct_estimated_unit_cogs_count,

    unit_cogs_values,
    override_actions,
    override_reasons,
    notes_examples,

    first_source_row_number,
    last_source_row_number,
    latest_loaded_at

FROM override_rollup;