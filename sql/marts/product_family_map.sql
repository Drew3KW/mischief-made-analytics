-- sql/marts/product_family_map.sql
-- Model: marts.product_family_map
-- Grain: one row per product_key
-- Purpose: reusable mapping from product_key to product_family_key
--
-- Notes:
-- - Built from marts.dim_products_historical
-- - Keeps family assignment logic centralized for downstream reuse
-- - Adds reusable business-facing family inclusion metadata
-- - Non-core families remain queryable, but can now be excluded consistently
--   by downstream analysis models via is_core_family

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.product_family_map` AS

WITH product_base AS (
    SELECT
        dph.product_key,
        dph.product_name,
        dph.sku,
        dph.source_type,

        LOWER(TRIM(dph.product_key)) AS normalized_product_key,
        LOWER(TRIM(dph.sku)) AS normalized_sku,

        REGEXP_REPLACE(
            LOWER(TRIM(dph.sku)),
            r'-(xxs|xs|s|m|l|xl|xxl|2x|2xl|3x|3xl|4x|4xl|5x|5xl|6x|6xl|3xk)$',
            ''
        ) AS normalized_sku_family,

        LOWER(TRIM(dph.product_name)) AS normalized_product_name,

        REGEXP_REPLACE(
            LOWER(TRIM(dph.product_name)),
            r'[^a-z0-9]+',
            '_'
        ) AS normalized_product_name_key,

        REGEXP_REPLACE(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    LOWER(TRIM(dph.product_name)),
                    r'[^a-z0-9]+',
                    '_'
                ),
                r'_(xx_small|x_small|small|medium|large|x_large|xx_large|xxx_large|xl|xxl|xxxl|1x|2x|3x|4x|5x|6x|1x_large|2x_large|3x_large|4x_large|5x_large|6x_large|2xl|3xl|4xl|5xl|6xl)$',
                ''
            ),
            r'_(design|art)_by_[a-z0-9_]+$',
            ''
        ) AS normalized_product_name_family_key
    FROM `mischief-made-analytics.marts.dim_products_historical` AS dph
),

family_logic AS (
    SELECT
        product_key,
        product_name,
        sku,
        source_type,

        CASE
            WHEN normalized_sku IS NOT NULL
             AND normalized_sku != ''
             AND normalized_sku NOT IN (
                'sticker', 'stickers',
                'greeting card', 'greeting-card', 'greeting_card',
                'card', 'cards',
                'patch', 'patches',
                'pin', 'pins',
                'magnet', 'magnets',
                'tote bag', 'tote-bag', 'tote_bag', 'tote',
                'decal', 'decal sticker'
             )
             AND normalized_sku_family NOT IN (
                'sticker', 'stickers',
                'greeting card', 'greeting-card', 'greeting_card',
                'card', 'cards',
                'patch', 'patches',
                'pin', 'pins',
                'magnet', 'magnets',
                'tote bag', 'tote-bag', 'tote_bag', 'tote',
                'decal', 'decal sticker'
             )
            THEN normalized_sku_family

            WHEN normalized_product_name IS NULL
              OR normalized_product_name = ''
              OR normalized_product_name IN (
                'sticker', 'stickers',
                'greeting card',
                'card', 'cards',
                'patch', 'patches',
                'pin', 'pins',
                'magnet', 'magnets',
                'tote bag', 'tote',
                'decal', 'decal sticker'
              )
            THEN normalized_product_key

            ELSE normalized_product_name_family_key
        END AS product_family_key,

        CASE
            WHEN product_name IS NOT NULL AND TRIM(product_name) != '' THEN product_name
            WHEN sku IS NOT NULL AND TRIM(sku) != '' THEN sku
            ELSE product_key
        END AS raw_product_family_name,

        CASE
            WHEN normalized_sku IS NOT NULL
             AND normalized_sku != ''
             AND normalized_sku NOT IN (
                'sticker', 'stickers',
                'greeting card', 'greeting-card', 'greeting_card',
                'card', 'cards',
                'patch', 'patches',
                'pin', 'pins',
                'magnet', 'magnets',
                'tote bag', 'tote-bag', 'tote_bag', 'tote',
                'decal', 'decal sticker'
             )
             AND normalized_sku_family NOT IN (
                'sticker', 'stickers',
                'greeting card', 'greeting-card', 'greeting_card',
                'card', 'cards',
                'patch', 'patches',
                'pin', 'pins',
                'magnet', 'magnets',
                'tote bag', 'tote-bag', 'tote_bag', 'tote',
                'decal', 'decal sticker'
             )
            THEN 'sku_family'

            WHEN normalized_product_name IS NULL
              OR normalized_product_name = ''
              OR normalized_product_name IN (
                'sticker', 'stickers',
                'greeting card',
                'card', 'cards',
                'patch', 'patches',
                'pin', 'pins',
                'magnet', 'magnets',
                'tote bag', 'tote',
                'decal', 'decal sticker'
              )
            THEN 'product_key_fallback'

            ELSE 'product_name_family'
        END AS family_assignment_method
    FROM product_base
),

cleaned_family_names AS (
    SELECT
        product_key,
        product_family_key,
        source_type,
        family_assignment_method,
        product_name,
        sku,
        raw_product_family_name,

        TRIM(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                raw_product_family_name,
                                r'^\[[^\]]+\]\s*',
                                ''
                            ),
                            r"(?i)\s*-\s*(unisex|ladies|womens|mens)?\s*-?\s*(xxs|xs|s|m|l|xl|xxl|xxxl|1x|2x|3x|4x|5x|6x|2xl|3xl|4xl|5xl|6xl|x-large|xx-large|xxx-large|2x-large|3x-large|4x-large|5x-large|6x-large)\s*$",
                            ''
                        ),
                        r'(?i)\s+(unisex|ladies|womens|mens)\s+body\s*$',
                        ''
                    ),
                    r'(?i)\s+(unisex|ladies|womens|mens)\s*$',
                    ''
                ),
                r'\s+',
                ' '
            )
        ) AS cleaned_product_family_name
    FROM family_logic
),

canonical_family_names AS (
    SELECT
        product_family_key,
        cleaned_product_family_name AS canonical_product_family_name
    FROM (
        SELECT
            product_family_key,
            cleaned_product_family_name,
            COUNT(*) AS product_rows,
            ROW_NUMBER() OVER (
                PARTITION BY product_family_key
                ORDER BY COUNT(*) DESC, LENGTH(cleaned_product_family_name) ASC, cleaned_product_family_name ASC
            ) AS rn
        FROM cleaned_family_names
        WHERE cleaned_product_family_name IS NOT NULL
          AND TRIM(cleaned_product_family_name) != ''
        GROUP BY
            product_family_key,
            cleaned_product_family_name
    )
    WHERE rn = 1
),

family_reporting_flags AS (
    SELECT
        product_family_key,
        canonical_product_family_name,

        CASE
            WHEN REGEXP_CONTAINS(
                LOWER(canonical_product_family_name),
                r'\b(mystery boxes?|gift (cards?|certificates?)|giftbox|gift box|stickers?|decals?|keychains?|greeting[ -]?cards?|pins?|patches?|magnets?)\b'
            ) THEN FALSE
            ELSE TRUE
        END AS is_core_family,

        CASE
            WHEN REGEXP_CONTAINS(
                LOWER(canonical_product_family_name),
                r'\b(mystery boxes?)\b'
            ) THEN 'non_core_mystery_box'
            WHEN REGEXP_CONTAINS(
                LOWER(canonical_product_family_name),
                r'\b(gift (cards?|certificates?)|giftbox|gift box)\b'
            ) THEN 'non_core_gift_item'
            WHEN REGEXP_CONTAINS(
                LOWER(canonical_product_family_name),
                r'\b(stickers?|decals?|keychains?|greeting[ -]?cards?|pins?|patches?|magnets?)\b'
            ) THEN 'non_core_accessory_or_promo'
            ELSE 'core_merchandise'
        END AS family_reporting_category,

        CASE
            WHEN REGEXP_CONTAINS(LOWER(canonical_product_family_name), r'\b(mystery boxes?)\b') THEN 'mystery_box'
            WHEN REGEXP_CONTAINS(LOWER(canonical_product_family_name), r'\b(gift (cards?|certificates?)|giftbox|gift box)\b') THEN 'gift_item'
            WHEN REGEXP_CONTAINS(LOWER(canonical_product_family_name), r'\b(stickers?)\b') THEN 'sticker'
            WHEN REGEXP_CONTAINS(LOWER(canonical_product_family_name), r'\b(decals?)\b') THEN 'decal'
            WHEN REGEXP_CONTAINS(LOWER(canonical_product_family_name), r'\b(keychains?)\b') THEN 'keychain'
            WHEN REGEXP_CONTAINS(LOWER(canonical_product_family_name), r'\b(greeting[ -]?cards?)\b') THEN 'greeting_card'
            WHEN REGEXP_CONTAINS(LOWER(canonical_product_family_name), r'\b(pins?)\b') THEN 'pin'
            WHEN REGEXP_CONTAINS(LOWER(canonical_product_family_name), r'\b(patches?)\b') THEN 'patch'
            WHEN REGEXP_CONTAINS(LOWER(canonical_product_family_name), r'\b(magnets?)\b') THEN 'magnet'
            ELSE NULL
        END AS family_exclusion_reason
    FROM canonical_family_names
)

SELECT
    cfn.product_key,
    cfn.product_family_key,
    cfn.cleaned_product_family_name,
    cfn.raw_product_family_name,
    cfn.product_name,
    cfn.sku,
    cfn.source_type,
    cfn.family_assignment_method,
    cfan.canonical_product_family_name,
    frf.is_core_family,
    frf.family_reporting_category,
    frf.family_exclusion_reason
FROM cleaned_family_names AS cfn
LEFT JOIN canonical_family_names AS cfan
    ON cfn.product_family_key = cfan.product_family_key
LEFT JOIN family_reporting_flags AS frf
    ON cfn.product_family_key = frf.product_family_key;
