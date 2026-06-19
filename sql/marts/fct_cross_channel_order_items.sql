-- sql/marts/fct_cross_channel_order_items.sql
-- Model: marts.fct_cross_channel_order_items
-- Grain:
-- One row per channel order item.
--
-- Purpose:
-- Combine Shopify and Etsy order-item facts into one cross-channel item-level
-- model with conservative COGS matching.
--
-- COGS resolution order:
-- 1. exact SKU match
-- 2. manual product-family override
-- 3. product-family match
-- 4. normalized product name/type match
-- 5. manual exclusion from profit model
-- 6. review or missing COGS status
--
-- Notes:
-- - Profit here is estimated gross profit before channel fees, ad spend, and
--   payout reconciliation.
-- - COGS coverage is intentionally visible through resolution and match fields.
-- - Duplicate/conflicting COGS evidence is not auto-accepted.

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.fct_cross_channel_order_items` AS

WITH usable_sku_cogs AS (
    SELECT
        normalized_sku,
        representative_sku,
        representative_family_name,
        unit_cogs,
        cogs_resolution_status,
        is_usable_for_profit_model,
        cogs_source,
        shopify_family_match_status
    FROM `mischief-made-analytics.marts.product_cogs_map`
    WHERE is_usable_for_profit_model = TRUE
      AND unit_cogs IS NOT NULL
),

all_sku_cogs AS (
    SELECT
        normalized_sku,
        cogs_resolution_status,
        is_usable_for_profit_model
    FROM `mischief-made-analytics.marts.product_cogs_map`
),

usable_override_cogs AS (
    SELECT
        product_family_key,
        unit_cogs,
        override_resolution_status,
        is_usable_for_profit_model,
        is_excluded_from_profit_model,
        cogs_source,
        override_row_count,
        distinct_estimated_unit_cogs_count
    FROM `mischief-made-analytics.marts.product_family_cogs_override_map`
    WHERE is_usable_for_profit_model = TRUE
      AND unit_cogs IS NOT NULL
),

all_override_cogs AS (
    SELECT
        product_family_key,
        override_resolution_status,
        is_usable_for_profit_model,
        is_excluded_from_profit_model,
        distinct_estimated_unit_cogs_count
    FROM `mischief-made-analytics.marts.product_family_cogs_override_map`
),

usable_family_cogs AS (
    SELECT
        product_family_key,
        product_family_name,
        unit_cogs,
        family_cogs_resolution_status,
        is_usable_for_profit_model,
        cogs_source,
        distinct_cogs_sku_count,
        distinct_unit_cogs_count
    FROM `mischief-made-analytics.marts.product_family_cogs_map`
    WHERE is_usable_for_profit_model = TRUE
      AND unit_cogs IS NOT NULL
),

all_family_cogs AS (
    SELECT
        product_family_key,
        family_cogs_resolution_status,
        is_usable_for_profit_model,
        distinct_unit_cogs_count
    FROM `mischief-made-analytics.marts.product_family_cogs_map`
),

usable_name_type_cogs AS (
    SELECT
        product_design_name_key,
        product_type_group,
        unit_cogs,
        name_type_cogs_resolution_status,
        is_usable_for_profit_model,
        cogs_source,
        distinct_cogs_sku_count,
        distinct_unit_cogs_count
    FROM `mischief-made-analytics.marts.product_name_type_cogs_map`
    WHERE is_usable_for_profit_model = TRUE
      AND unit_cogs IS NOT NULL
),

all_name_type_cogs AS (
    SELECT
        product_design_name_key,
        product_type_group,
        name_type_cogs_resolution_status,
        is_usable_for_profit_model,
        distinct_unit_cogs_count
    FROM `mischief-made-analytics.marts.product_name_type_cogs_map`
),

shopify_items AS (
    SELECT
        'shopify' AS channel,

        CONCAT('shopify:', oi.order_item_key) AS cross_channel_order_item_key,
        CONCAT('shopify:', oi.order_number) AS cross_channel_order_key,

        oi.order_item_key AS source_order_item_key,
        oi.order_number AS source_order_key,
        CAST(oi.shopify_order_id AS STRING) AS source_order_id,

        cb.cross_channel_customer_key,

        oi.created_at_ts AS order_created_at,
        DATE(oi.created_at_ts) AS order_date,
        oi.paid_at_ts AS paid_at,
        oi.fulfilled_at_ts,
        oi.cancelled_at_ts,

        oi.customer_email AS source_customer_key,
        oi.customer_email AS customer_email,

        oi.product_key AS source_product_key,
        oi.product_key,
        pfm.product_family_key,
        pfm.canonical_product_family_name AS product_family_name,

        CONCAT('product_family:', pfm.product_family_key) AS cross_channel_product_family_key,

        CAST(NULL AS STRING) AS etsy_listing_id,
        CAST(NULL AS STRING) AS etsy_listing_key,

        oi.sku,
        LOWER(NULLIF(TRIM(oi.sku), '')) AS normalized_sku,
        oi.product_name AS product_name,

        oi.quantity,
        oi.lineitem_price AS item_unit_price,
        oi.lineitem_discount AS item_discount_amount,

        oi.gross_item_revenue,
        oi.net_item_revenue_before_refunds,

        oi.currency,
        oi.financial_status,
        oi.fulfillment_status,
        oi.lineitem_fulfillment_status,

        FALSE AS has_blank_sku,
        FALSE AS missing_receipt_record,

        oi.vendor,
        oi.order_source,
        oi.shipping_city,
        oi.shipping_province,
        oi.shipping_country,

        'shopify_line_item' AS source_item_type
    FROM `mischief-made-analytics.marts.fct_order_items` AS oi
    LEFT JOIN `mischief-made-analytics.marts.product_family_map` AS pfm
        ON oi.product_key = pfm.product_key
    LEFT JOIN `mischief-made-analytics.marts.cross_channel_customer_bridge` AS cb
        ON cb.source_channel = 'shopify'
        AND cb.source_customer_key = oi.customer_email
),

etsy_items AS (
    SELECT
        'etsy' AS channel,

        oi.cross_channel_order_item_key,
        oi.cross_channel_order_key,

        oi.etsy_order_item_key AS source_order_item_key,
        oi.etsy_order_key AS source_order_key,
        CAST(oi.receipt_id AS STRING) AS source_order_id,

        cb.cross_channel_customer_key,

        oi.order_created_at,
        oi.order_date,
        oi.paid_at,
        oi.shipped_at AS fulfilled_at_ts,
        CAST(NULL AS TIMESTAMP) AS cancelled_at_ts,

        oi.etsy_buyer_key AS source_customer_key,
        oi.buyer_email AS customer_email,

        oi.etsy_product_key AS source_product_key,
        oi.etsy_product_key AS product_key,

        pfb.mapped_product_family_key AS product_family_key,
        pfb.mapped_product_family_name AS product_family_name,
        pfb.cross_channel_product_family_key,

        CAST(oi.listing_id AS STRING) AS etsy_listing_id,
        oi.etsy_listing_key,

        oi.sku,
        LOWER(NULLIF(TRIM(oi.sku), '')) AS normalized_sku,
        oi.listing_title AS product_name,

        oi.quantity,
        oi.item_price AS item_unit_price,
        COALESCE(oi.buyer_coupon_amount, 0)
            + COALESCE(oi.shop_coupon_amount, 0) AS item_discount_amount,

        oi.item_gross_amount AS gross_item_revenue,
        oi.item_gross_amount
            - COALESCE(oi.buyer_coupon_amount, 0)
            - COALESCE(oi.shop_coupon_amount, 0) AS net_item_revenue_before_refunds,

        oi.item_price_currency AS currency,

        CASE
            WHEN oi.is_paid THEN 'paid'
            ELSE 'not_paid_or_unknown'
        END AS financial_status,

        CASE
            WHEN oi.is_shipped THEN 'fulfilled'
            ELSE 'unfulfilled_or_unknown'
        END AS fulfillment_status,

        CAST(NULL AS STRING) AS lineitem_fulfillment_status,

        oi.has_blank_sku,
        oi.missing_receipt_record,

        CAST(NULL AS STRING) AS vendor,
        'etsy' AS order_source,
        CAST(NULL AS STRING) AS shipping_city,
        CAST(NULL AS STRING) AS shipping_province,
        CAST(NULL AS STRING) AS shipping_country,

        'etsy_receipt_transaction' AS source_item_type
    FROM `mischief-made-analytics.marts.fct_etsy_order_items` AS oi
    LEFT JOIN `mischief-made-analytics.marts.cross_channel_customer_bridge` AS cb
        ON cb.source_channel = 'etsy'
        AND cb.source_customer_key = oi.etsy_buyer_key
    LEFT JOIN `mischief-made-analytics.marts.cross_channel_product_family_bridge` AS pfb
        ON pfb.source_channel = 'etsy'
        AND pfb.source_entity_type = 'etsy_listing'
        AND pfb.source_listing_id = CAST(oi.listing_id AS STRING)
),

combined_items AS (
    SELECT * FROM shopify_items
    UNION ALL
    SELECT * FROM etsy_items
),

items_with_name_type_keys AS (
    SELECT
        i.*,

        COALESCE(i.product_family_name, i.product_name) AS cogs_name_source_text,

        CASE
            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(cardigan|sweater|pullover|knit)\b') THEN 'knitwear'
            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(tee|tshirt|t-shirt|shirt|raglan|ringer)\b') THEN 'tee'
            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(tank|top)\b') THEN 'tank_top'
            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(dress)\b') THEN 'dress'
            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(skirt)\b') THEN 'skirt'
            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(purse|bag)\b') THEN 'bag'
            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(pin|patch|corsage)\b') THEN 'accessory'
            ELSE 'unknown'
        END AS item_product_type_group,

        CASE
            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(gift card|mystery box|post card|postcard)\b')
                THEN 'excluded_non_product_or_bundle'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(hoodie)\b')
                THEN 'hoodie'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(pullover fleece|fleece)\b')
              OR REGEXP_EXTRACT(LOWER(COALESCE(i.product_family_key, '')), r'^([a-z]+)') = 'pu'
                THEN 'pullover_fleece'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(turtleneck)\b')
              OR REGEXP_EXTRACT(LOWER(COALESCE(i.product_family_key, '')), r'^([a-z]+)') = 'tu'
                THEN 'turtleneck_sweater'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(short sleeve|short-sleeve)\b')
              AND REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(sweater|knit|pullover)\b')
                THEN 'short_sleeve_sweater'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(collared)\b')
              AND REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(cropped|crop)\b')
              AND REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(sweater|knit)\b')
                THEN 'collared_cropped_sweater'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(cropped|crop)\b')
              AND REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(cardigan)\b')
                THEN 'cropped_cardigan'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(cardigan)\b')
                THEN 'cardigan'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(beanie)\b')
                THEN 'beanie'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(sweater|pullover|knit)\b')
                THEN 'sweater'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(kids|kid|baby-kids|baby kids|baby boy|size nb|nb,|6m|12m|2t|3t|4t|5/6t|7t)\b')
              OR REGEXP_EXTRACT(LOWER(COALESCE(i.product_family_key, '')), r'^([a-z]+)') = 'tsk'
                THEN 'kids_tee'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r"\b(men'?s|men |delinquent bros)\b")
              OR REGEXP_EXTRACT(LOWER(COALESCE(i.product_family_key, '')), r'^([a-z]+)') = 'tsm'
                THEN 'mens_tee'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(long sleeve|long-sleeve)\b')
              AND REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(tee|tshirt|t-shirt|shirt)\b')
                THEN 'long_sleeve_tee'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(raglan)\b')
                THEN 'raglan_tee'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(ringer)\b')
                THEN 'ringer_tee'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(rib racer|racer tank)\b')
                THEN 'rib_racer_tank'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(tank|top)\b')
                THEN 'tank_top'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(fitted|baby tee)\b')
                THEN 'fitted_tee'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(cropped tee|crop tee|cropped t-shirt|crop t-shirt|cropped tshirt|crop tshirt)\b')
                THEN 'cropped_tee'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(boxy tee|boxy t-shirt|boxy tshirt)\b')
                THEN 'boxy_tee'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(mini tee|mini t-shirt|mini tshirt)\b')
                THEN 'mini_tee'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(tee|tshirt|t-shirt|shirt)\b')
                THEN 'standard_tee'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(pill case)\b')
                THEN 'pill_case'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(collar)\b')
                THEN 'collar'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(tote)\b')
                THEN 'tote_bag'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(crossbody)\b')
                THEN 'crossbody_bag'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(purse|bag)\b')
                THEN 'bag'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(dress)\b')
                THEN 'dress'

            WHEN REGEXP_CONTAINS(LOWER(COALESCE(i.product_family_name, i.product_name)), r'\b(skirt)\b')
                THEN 'skirt'

            ELSE 'unknown'
        END AS item_product_subtype_group,

        REGEXP_REPLACE(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                    LOWER(TRIM(COALESCE(i.product_family_name, i.product_name))),
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
        ) AS item_product_design_name_key
    FROM combined_items AS i
),

with_cogs AS (
    SELECT
        i.*,

        COALESCE(
            sku_cogs.unit_cogs,
            override_cogs.unit_cogs,
            family_cogs.unit_cogs,
            name_type_cogs.unit_cogs
        ) AS unit_cogs,

        CASE
            WHEN sku_cogs.normalized_sku IS NOT NULL THEN sku_cogs.cogs_source
            WHEN override_cogs.product_family_key IS NOT NULL THEN override_cogs.cogs_source
            WHEN family_cogs.product_family_key IS NOT NULL THEN family_cogs.cogs_source
            WHEN name_type_cogs.product_design_name_key IS NOT NULL THEN name_type_cogs.cogs_source
            WHEN all_override_cogs.is_excluded_from_profit_model THEN 'manual_product_family_override'
            ELSE NULL
        END AS cogs_source,

        CASE
            WHEN sku_cogs.normalized_sku IS NOT NULL THEN 'sku_match'
            WHEN override_cogs.product_family_key IS NOT NULL THEN 'manual_product_family_override'
            WHEN family_cogs.product_family_key IS NOT NULL THEN 'product_family_match'
            WHEN name_type_cogs.product_design_name_key IS NOT NULL THEN 'name_type_match'
            WHEN all_override_cogs.is_excluded_from_profit_model THEN 'manual_exclusion'
            WHEN i.normalized_sku IS NULL THEN 'missing_sku'
            WHEN all_sku_cogs.normalized_sku IS NOT NULL
              AND all_sku_cogs.cogs_resolution_status = 'duplicate_sku_conflict'
                THEN 'duplicate_sku_conflict'
            WHEN all_sku_cogs.normalized_sku IS NOT NULL
              AND all_sku_cogs.cogs_resolution_status = 'missing_cogs'
                THEN 'missing_cogs'
            WHEN all_override_cogs.product_family_key IS NOT NULL
              AND all_override_cogs.override_resolution_status IN ('override_conflict', 'invalid_override')
                THEN 'manual_override_conflict'
            WHEN all_family_cogs.product_family_key IS NOT NULL
              AND all_family_cogs.family_cogs_resolution_status = 'product_family_cogs_conflict'
                THEN 'product_family_cogs_conflict'
            WHEN all_name_type_cogs.product_design_name_key IS NOT NULL
              AND all_name_type_cogs.name_type_cogs_resolution_status = 'name_type_cogs_conflict'
                THEN 'name_type_cogs_conflict'
            ELSE 'no_cogs_record'
        END AS cogs_match_type,

        CASE
            WHEN sku_cogs.normalized_sku IS NOT NULL THEN 'accepted'
            WHEN override_cogs.product_family_key IS NOT NULL THEN 'accepted'
            WHEN family_cogs.product_family_key IS NOT NULL THEN 'accepted'
            WHEN name_type_cogs.product_design_name_key IS NOT NULL THEN 'accepted'
            WHEN all_override_cogs.is_excluded_from_profit_model THEN 'excluded_from_profit_model'
            WHEN i.normalized_sku IS NULL THEN 'missing_sku'
            WHEN all_sku_cogs.normalized_sku IS NOT NULL
              AND all_sku_cogs.cogs_resolution_status = 'duplicate_sku_conflict'
                THEN 'review_conflict'
            WHEN all_sku_cogs.normalized_sku IS NOT NULL
              AND all_sku_cogs.cogs_resolution_status = 'missing_cogs'
                THEN 'missing_cogs'
            WHEN all_override_cogs.product_family_key IS NOT NULL
              AND all_override_cogs.override_resolution_status IN ('override_conflict', 'invalid_override')
                THEN 'review_conflict'
            WHEN all_family_cogs.product_family_key IS NOT NULL
              AND all_family_cogs.family_cogs_resolution_status = 'product_family_cogs_conflict'
                THEN 'review_conflict'
            WHEN all_name_type_cogs.product_design_name_key IS NOT NULL
              AND all_name_type_cogs.name_type_cogs_resolution_status = 'name_type_cogs_conflict'
                THEN 'review_conflict'
            ELSE 'missing_cogs'
        END AS cogs_resolution_status,

        CASE
            WHEN sku_cogs.normalized_sku IS NOT NULL THEN 'sku'
            WHEN override_cogs.product_family_key IS NOT NULL THEN 'manual_product_family_override'
            WHEN family_cogs.product_family_key IS NOT NULL THEN 'product_family'
            WHEN name_type_cogs.product_design_name_key IS NOT NULL THEN 'name_type'
            WHEN all_override_cogs.is_excluded_from_profit_model THEN 'manual_exclusion'
            ELSE NULL
        END AS cogs_match_grain,

        sku_cogs.shopify_family_match_status AS cogs_shopify_family_match_status,

        override_cogs.override_resolution_status AS cogs_override_resolution_status,
        override_cogs.override_row_count AS cogs_override_row_count,
        override_cogs.distinct_estimated_unit_cogs_count AS cogs_override_distinct_unit_cogs_count,

        CASE
            WHEN all_override_cogs.is_excluded_from_profit_model THEN TRUE
            ELSE FALSE
        END AS is_excluded_from_profit_model,

        family_cogs.family_cogs_resolution_status,
        family_cogs.distinct_cogs_sku_count AS family_cogs_distinct_sku_count,
        family_cogs.distinct_unit_cogs_count AS family_cogs_distinct_unit_cogs_count,

        name_type_cogs.name_type_cogs_resolution_status,
        name_type_cogs.distinct_cogs_sku_count AS name_type_cogs_distinct_sku_count,
        name_type_cogs.distinct_unit_cogs_count AS name_type_cogs_distinct_unit_cogs_count

    FROM items_with_name_type_keys AS i
    LEFT JOIN usable_sku_cogs AS sku_cogs
        ON i.normalized_sku = sku_cogs.normalized_sku
    LEFT JOIN all_sku_cogs
        ON i.normalized_sku = all_sku_cogs.normalized_sku
    LEFT JOIN usable_override_cogs AS override_cogs
        ON LOWER(i.product_family_key) = override_cogs.product_family_key
    LEFT JOIN all_override_cogs
        ON LOWER(i.product_family_key) = all_override_cogs.product_family_key
    LEFT JOIN usable_family_cogs AS family_cogs
        ON LOWER(i.product_family_key) = family_cogs.product_family_key
    LEFT JOIN all_family_cogs
        ON LOWER(i.product_family_key) = all_family_cogs.product_family_key
    LEFT JOIN usable_name_type_cogs AS name_type_cogs
        ON i.item_product_design_name_key = name_type_cogs.product_design_name_key
        AND i.item_product_type_group = name_type_cogs.product_type_group
    LEFT JOIN all_name_type_cogs
        ON i.item_product_design_name_key = all_name_type_cogs.product_design_name_key
        AND i.item_product_type_group = all_name_type_cogs.product_type_group
)

SELECT
    channel,
    cross_channel_order_item_key,
    cross_channel_order_key,
    source_order_item_key,
    source_order_key,
    source_order_id,
    cross_channel_customer_key,

    order_created_at,
    order_date,
    paid_at,
    fulfilled_at_ts,
    cancelled_at_ts,

    source_customer_key,
    customer_email,

    source_product_key,
    product_key,
    product_family_key,
    product_family_name,
    cross_channel_product_family_key,
    etsy_listing_id,
    etsy_listing_key,

    cogs_name_source_text,
    item_product_design_name_key,
    item_product_type_group,
    item_product_subtype_group,

    sku,
    normalized_sku,
    product_name,

    quantity,
    item_unit_price,
    item_discount_amount,
    gross_item_revenue,
    net_item_revenue_before_refunds,

    unit_cogs,
    cogs_source,
    cogs_match_type,
    cogs_resolution_status,
    cogs_match_grain,

    cogs_shopify_family_match_status,

    cogs_override_resolution_status,
    cogs_override_row_count,
    cogs_override_distinct_unit_cogs_count,
    is_excluded_from_profit_model,

    family_cogs_resolution_status,
    family_cogs_distinct_sku_count,
    family_cogs_distinct_unit_cogs_count,

    name_type_cogs_resolution_status,
    name_type_cogs_distinct_sku_count,
    name_type_cogs_distinct_unit_cogs_count,

    CASE
        WHEN unit_cogs IS NOT NULL THEN quantity * unit_cogs
        ELSE NULL
    END AS estimated_item_cogs,

    CASE
        WHEN unit_cogs IS NOT NULL
            THEN net_item_revenue_before_refunds - (quantity * unit_cogs)
        ELSE NULL
    END AS estimated_gross_profit_before_fees,

    CASE
        WHEN unit_cogs IS NOT NULL
          AND net_item_revenue_before_refunds != 0
            THEN SAFE_DIVIDE(
                net_item_revenue_before_refunds - (quantity * unit_cogs),
                net_item_revenue_before_refunds
            )
        ELSE NULL
    END AS estimated_gross_margin_before_fees,

    currency,
    financial_status,
    fulfillment_status,
    lineitem_fulfillment_status,

    has_blank_sku,
    missing_receipt_record,

    vendor,
    order_source,
    shipping_city,
    shipping_province,
    shipping_country,

    source_item_type

FROM with_cogs;