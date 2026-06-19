-- sql/marts/product_name_type_cogs_map.sql
-- Model: marts.product_name_type_cogs_map
-- Grain:
-- One row per normalized product design name and product type group.
--
-- Purpose:
-- Create a conservative name/type COGS fallback from accepted manual COGS
-- records.
--
-- Notes:
-- - This fallback is used after exact SKU and exact product-family matching.
-- - It requires both normalized design name and product type group to match.
-- - It is usable only when all COGS evidence for that name/type pair points
--   to one distinct unit_cogs value.
-- - Name/type conflicts remain visible and are not used automatically.

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.product_name_type_cogs_map` AS

WITH accepted_cogs AS (
    SELECT
        normalized_sku,
        representative_sku,
        representative_family_name,
        unit_cogs,
        cogs_source,

        CASE
            WHEN REGEXP_CONTAINS(LOWER(representative_family_name), r'\b(cardigan|sweater|pullover|knit)\b') THEN 'knitwear'
            WHEN REGEXP_CONTAINS(LOWER(representative_family_name), r'\b(tee|tshirt|t-shirt|shirt|raglan|ringer)\b') THEN 'tee'
            WHEN REGEXP_CONTAINS(LOWER(representative_family_name), r'\b(tank|top)\b') THEN 'tank_top'
            WHEN REGEXP_CONTAINS(LOWER(representative_family_name), r'\b(dress)\b') THEN 'dress'
            WHEN REGEXP_CONTAINS(LOWER(representative_family_name), r'\b(skirt)\b') THEN 'skirt'
            WHEN REGEXP_CONTAINS(LOWER(representative_family_name), r'\b(purse|bag)\b') THEN 'bag'
            WHEN REGEXP_CONTAINS(LOWER(representative_family_name), r'\b(pin|patch|corsage)\b') THEN 'accessory'
            ELSE 'unknown'
        END AS product_type_group,

        REGEXP_REPLACE(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                    LOWER(TRIM(representative_family_name)),
                                    r'\s*\([^)]*\)\s*',
                                    ' '
                                ),
                                r'\b(in|by|design|art|shop|mischief|made|the|and|of|x)\b',
                                ' '
                            ),
                            r'\b(black|white|ivory|cream|natural|navy|red|pink|blue|green|purple|orange|peach|gold|silver|brown|beige|heather|forest|vintage|dusty|antique|honey|lavender)\b',
                            ' '
                        ),
                        r'\b(fitted|unisex|cropped|crop|short|sleeve|sleeved|sleeves|raglan|ringer|baby|mini|oversized|collared|knit|pullover)\b',
                        ' '
                    ),
                    r'\b(tee|tshirt|t-shirt|shirt|cardigan|sweater|tank|top|dress|skirt|corsage|purse|bag|pin|patch)\b',
                    ' '
                ),
                r'[^a-z0-9]+',
                '_'
            ),
            r'(^_+|_+$)',
            ''
        ) AS product_design_name_key
    FROM `mischief-made-analytics.marts.product_cogs_map`
    WHERE is_usable_for_profit_model = TRUE
      AND unit_cogs IS NOT NULL
      AND representative_family_name IS NOT NULL
),

name_type_rollup AS (
    SELECT
        product_design_name_key,
        product_type_group,

        COUNT(*) AS source_cogs_row_count,
        COUNT(DISTINCT normalized_sku) AS distinct_cogs_sku_count,
        COUNT(DISTINCT unit_cogs) AS distinct_unit_cogs_count,

        ARRAY_AGG(DISTINCT representative_sku IGNORE NULLS LIMIT 10) AS cogs_sku_examples,
        ARRAY_AGG(DISTINCT representative_family_name IGNORE NULLS LIMIT 10) AS cogs_family_name_examples,
        ARRAY_AGG(DISTINCT unit_cogs IGNORE NULLS ORDER BY unit_cogs LIMIT 10) AS unit_cogs_values,

        MIN(unit_cogs) AS min_unit_cogs,
        MAX(unit_cogs) AS max_unit_cogs
    FROM accepted_cogs
    WHERE product_design_name_key IS NOT NULL
      AND product_design_name_key != ''
      AND product_type_group != 'unknown'
      AND LENGTH(product_design_name_key) >= 4
    GROUP BY
        product_design_name_key,
        product_type_group
)

SELECT
    product_design_name_key,
    product_type_group,

    CASE
        WHEN distinct_unit_cogs_count = 1 THEN unit_cogs_values[SAFE_OFFSET(0)]
        ELSE NULL
    END AS unit_cogs,

    CASE
        WHEN distinct_unit_cogs_count = 1 THEN 'accepted_name_type'
        WHEN distinct_unit_cogs_count > 1 THEN 'name_type_cogs_conflict'
        ELSE 'review'
    END AS name_type_cogs_resolution_status,

    CASE
        WHEN distinct_unit_cogs_count = 1 THEN TRUE
        ELSE FALSE
    END AS is_usable_for_profit_model,

    'manual_csv_name_type_fallback' AS cogs_source,

    source_cogs_row_count,
    distinct_cogs_sku_count,
    distinct_unit_cogs_count,
    cogs_sku_examples,
    cogs_family_name_examples,
    unit_cogs_values,
    min_unit_cogs,
    max_unit_cogs
FROM name_type_rollup;