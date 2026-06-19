-- sql/marts/product_family_cogs_map.sql
-- Model: marts.product_family_cogs_map
-- Grain:
-- One row per Shopify product_family_key with available manual COGS evidence.
--
-- Purpose:
-- Create a conservative product-family-level COGS fallback from accepted
-- SKU-level COGS records.
--
-- Notes:
-- - This model only uses SKU COGS records accepted in product_cogs_map.
-- - A product family is usable only when all accepted SKU COGS evidence points
--   to one distinct unit_cogs value.
-- - Families with multiple distinct COGS values remain visible as conflicts.

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.product_family_cogs_map` AS

WITH accepted_sku_cogs AS (
    SELECT
        normalized_sku,
        representative_sku,
        representative_family_name,
        unit_cogs,
        cogs_source
    FROM `mischief-made-analytics.marts.product_cogs_map`
    WHERE is_usable_for_profit_model = TRUE
      AND unit_cogs IS NOT NULL
),

sku_to_family AS (
    SELECT
        LOWER(TRIM(sku)) AS normalized_sku,
        product_family_key,
        canonical_product_family_name AS product_family_name
    FROM `mischief-made-analytics.marts.product_family_map`
    WHERE sku IS NOT NULL
      AND TRIM(sku) != ''
      AND product_family_key IS NOT NULL
),

family_rollup AS (
    SELECT
        f.product_family_key,
        ANY_VALUE(f.product_family_name) AS product_family_name,

        COUNT(*) AS source_sku_cogs_row_count,
        COUNT(DISTINCT c.normalized_sku) AS distinct_cogs_sku_count,
        COUNT(DISTINCT c.unit_cogs) AS distinct_unit_cogs_count,

        ARRAY_AGG(DISTINCT c.representative_sku IGNORE NULLS LIMIT 10) AS cogs_sku_examples,
        ARRAY_AGG(DISTINCT c.representative_family_name IGNORE NULLS LIMIT 10) AS cogs_family_name_examples,
        ARRAY_AGG(DISTINCT c.unit_cogs IGNORE NULLS ORDER BY c.unit_cogs LIMIT 10) AS unit_cogs_values,

        MIN(c.unit_cogs) AS min_unit_cogs,
        MAX(c.unit_cogs) AS max_unit_cogs
    FROM accepted_sku_cogs AS c
    INNER JOIN sku_to_family AS f
        ON c.normalized_sku = f.normalized_sku
    GROUP BY
        f.product_family_key
)

SELECT
    product_family_key,
    product_family_name,

    CASE
        WHEN distinct_unit_cogs_count = 1 THEN unit_cogs_values[SAFE_OFFSET(0)]
        ELSE NULL
    END AS unit_cogs,

    CASE
        WHEN distinct_unit_cogs_count = 1 THEN 'accepted_family'
        WHEN distinct_unit_cogs_count > 1 THEN 'product_family_cogs_conflict'
        ELSE 'review'
    END AS family_cogs_resolution_status,

    CASE
        WHEN distinct_unit_cogs_count = 1 THEN TRUE
        ELSE FALSE
    END AS is_usable_for_profit_model,

    'manual_csv_family_fallback' AS cogs_source,

    source_sku_cogs_row_count,
    distinct_cogs_sku_count,
    distinct_unit_cogs_count,
    cogs_sku_examples,
    cogs_family_name_examples,
    unit_cogs_values,
    min_unit_cogs,
    max_unit_cogs
FROM family_rollup;