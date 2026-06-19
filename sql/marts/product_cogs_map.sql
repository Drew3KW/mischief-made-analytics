-- sql/marts/product_cogs_map.sql
-- Model: marts.product_cogs_map
-- Grain:
-- One row per normalized SKU from the manual COGS source.
--
-- Purpose:
-- Create a conservative SKU-level COGS map from the private manual COGS CSV.
--
-- Notes:
-- - The source CSV is loaded into raw_load.product_cogs_manual_latest.
-- - Only unique SKU rows with one distinct unit_cogs value are usable for profit modeling.
-- - Duplicate SKUs with conflicting costs remain visible but are not usable.
-- - Rows without SKUs are not included in this SKU-level map.

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.product_cogs_map` AS

WITH raw_cogs AS (
    SELECT
        source_file_name,
        source_row_number,
        loaded_at,
        sku,
        normalized_sku,
        family_name,
        normalized_family_name,
        price_raw,
        profit_raw,
        faire_15_fee_amount_raw,
        faire_profit_raw,
        cost_raw,
        reference_price,
        reference_profit,
        reference_faire_15_fee_amount,
        reference_faire_profit,
        unit_cogs,
        raw_notes_1
    FROM `mischief-made-analytics.raw_load.product_cogs_manual_latest`
    WHERE normalized_sku IS NOT NULL
),

shopify_sku_lookup AS (
    SELECT
        LOWER(TRIM(sku)) AS normalized_sku,
        COUNT(DISTINCT product_family_key) AS shopify_product_family_count,
        ARRAY_AGG(DISTINCT product_family_key IGNORE NULLS LIMIT 5) AS shopify_product_family_keys,
        ARRAY_AGG(DISTINCT canonical_product_family_name IGNORE NULLS LIMIT 5) AS shopify_product_family_names
    FROM `mischief-made-analytics.marts.product_family_map`
    WHERE sku IS NOT NULL
      AND TRIM(sku) != ''
    GROUP BY
        normalized_sku
),

sku_rollup AS (
    SELECT
        normalized_sku,

        COUNT(*) AS source_row_count,
        COUNTIF(unit_cogs IS NOT NULL) AS source_rows_with_unit_cogs,
        COUNT(DISTINCT unit_cogs) AS distinct_unit_cogs_count,

        ARRAY_AGG(DISTINCT sku IGNORE NULLS LIMIT 5) AS sku_examples,
        ARRAY_AGG(DISTINCT family_name IGNORE NULLS LIMIT 5) AS family_name_examples,
        ARRAY_AGG(DISTINCT cost_raw IGNORE NULLS LIMIT 5) AS cost_raw_examples,
        ARRAY_AGG(DISTINCT price_raw IGNORE NULLS LIMIT 5) AS price_raw_examples,
        ARRAY_AGG(DISTINCT profit_raw IGNORE NULLS LIMIT 5) AS profit_raw_examples,

        ARRAY_AGG(DISTINCT unit_cogs IGNORE NULLS ORDER BY unit_cogs LIMIT 5) AS unit_cogs_values,
        ARRAY_AGG(DISTINCT reference_price IGNORE NULLS ORDER BY reference_price LIMIT 5) AS reference_price_values,
        ARRAY_AGG(DISTINCT reference_profit IGNORE NULLS ORDER BY reference_profit LIMIT 5) AS reference_profit_values,
        ARRAY_AGG(DISTINCT reference_faire_15_fee_amount IGNORE NULLS ORDER BY reference_faire_15_fee_amount LIMIT 5) AS reference_faire_15_fee_amount_values,
        ARRAY_AGG(DISTINCT reference_faire_profit IGNORE NULLS ORDER BY reference_faire_profit LIMIT 5) AS reference_faire_profit_values,

        MIN(source_row_number) AS first_source_row_number,
        MAX(source_row_number) AS last_source_row_number,
        MAX(loaded_at) AS latest_loaded_at
    FROM raw_cogs
    GROUP BY
        normalized_sku
)

SELECT
    r.normalized_sku,

    r.sku_examples[SAFE_OFFSET(0)] AS representative_sku,
    r.family_name_examples[SAFE_OFFSET(0)] AS representative_family_name,

    CASE
        WHEN r.source_rows_with_unit_cogs = 0 THEN NULL
        WHEN r.distinct_unit_cogs_count = 1 THEN r.unit_cogs_values[SAFE_OFFSET(0)]
        ELSE NULL
    END AS unit_cogs,

    CASE
        WHEN r.source_rows_with_unit_cogs = 0 THEN 'missing_cogs'
        WHEN r.distinct_unit_cogs_count = 1 THEN 'accepted_sku'
        WHEN r.distinct_unit_cogs_count > 1 THEN 'duplicate_sku_conflict'
        ELSE 'review'
    END AS cogs_resolution_status,

    CASE
        WHEN r.distinct_unit_cogs_count = 1 THEN TRUE
        ELSE FALSE
    END AS is_usable_for_profit_model,

    'manual_csv' AS cogs_source,

    r.source_row_count,
    r.source_rows_with_unit_cogs,
    r.distinct_unit_cogs_count,

    r.sku_examples,
    r.family_name_examples,
    r.cost_raw_examples,
    r.price_raw_examples,
    r.profit_raw_examples,

    r.unit_cogs_values,
    r.reference_price_values,
    r.reference_profit_values,
    r.reference_faire_15_fee_amount_values,
    r.reference_faire_profit_values,

    r.first_source_row_number,
    r.last_source_row_number,
    r.latest_loaded_at,

    COALESCE(s.shopify_product_family_count, 0) AS shopify_product_family_count,
    s.shopify_product_family_keys,
    s.shopify_product_family_names,

    CASE
        WHEN s.normalized_sku IS NULL THEN 'not_found_in_shopify_product_family_map'
        WHEN s.shopify_product_family_count = 1 THEN 'single_shopify_family_match'
        WHEN s.shopify_product_family_count > 1 THEN 'multiple_shopify_family_matches'
        ELSE 'review'
    END AS shopify_family_match_status

FROM sku_rollup AS r
LEFT JOIN shopify_sku_lookup AS s
    ON r.normalized_sku = s.normalized_sku;