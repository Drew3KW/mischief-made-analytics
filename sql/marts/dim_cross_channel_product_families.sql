-- sql/marts/dim_cross_channel_product_families.sql
-- Model: marts.dim_cross_channel_product_families
-- Grain:
-- One row per cross_channel_product_family_key.
--
-- Purpose:
-- Create a conservative cross-channel product-family dimension from the
-- explicit product-family bridge.
--
-- Notes:
-- - Accepted Etsy SKU matches roll up into Shopify product-family keys.
-- - Etsy title-pattern matches remain review candidates.
-- - Unresolved Etsy listings remain visible and are not forced into a family.

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.dim_cross_channel_product_families` AS

WITH bridge AS (
    SELECT *
    FROM `mischief-made-analytics.marts.cross_channel_product_family_bridge`
)

SELECT
    cross_channel_product_family_key,

    CASE
        WHEN COUNTIF(source_channel = 'shopify') > 0
          AND COUNTIF(source_channel = 'etsy' AND bridge_resolution_status = 'accepted') > 0
            THEN 'cross_channel_accepted'
        WHEN COUNTIF(source_channel = 'shopify') > 0
          AND COUNTIF(source_channel = 'etsy') = 0
            THEN 'shopify_only'
        WHEN COUNTIF(source_channel = 'etsy' AND bridge_resolution_status = 'review_candidate') > 0
            THEN 'etsy_review_candidate'
        WHEN COUNTIF(source_channel = 'etsy' AND bridge_resolution_status = 'unresolved') > 0
            THEN 'etsy_unresolved'
        ELSE 'review'
    END AS product_family_identity_status,

    ARRAY_TO_STRING(
        ARRAY_AGG(DISTINCT source_channel ORDER BY source_channel),
        ', '
    ) AS source_channels_present,

    COUNT(*) AS bridge_row_count,
    COUNT(DISTINCT source_channel) AS source_channel_count,

    COUNTIF(source_channel = 'shopify') AS shopify_family_bridge_row_count,
    COUNTIF(source_channel = 'etsy') AS etsy_listing_bridge_row_count,

    COUNTIF(source_channel = 'etsy' AND bridge_resolution_status = 'accepted') AS accepted_etsy_listing_count,
    COUNTIF(source_channel = 'etsy' AND bridge_resolution_status = 'review_candidate') AS review_candidate_etsy_listing_count,
    COUNTIF(source_channel = 'etsy' AND bridge_resolution_status = 'unresolved') AS unresolved_etsy_listing_count,

    COALESCE(
        MAX(IF(source_channel = 'shopify', source_product_family_key, NULL)),
        MAX(mapped_product_family_key),
        MAX(candidate_product_family_key)
    ) AS mapped_product_family_key,

    COALESCE(
        MAX(IF(source_channel = 'shopify', source_product_name, NULL)),
        MAX(mapped_product_family_name),
        MAX(candidate_product_family_name),
        ARRAY_AGG(source_product_name IGNORE NULLS ORDER BY last_sold_date DESC LIMIT 1)[SAFE_OFFSET(0)]
    ) AS product_family_name,

    MAX(IF(source_channel = 'shopify', source_product_family_key, NULL)) AS shopify_product_family_key,

    ARRAY_TO_STRING(
        ARRAY_AGG(DISTINCT match_type ORDER BY match_type),
        ', '
    ) AS match_types_present,

    ARRAY_TO_STRING(
        ARRAY_AGG(DISTINCT match_subtype IGNORE NULLS ORDER BY match_subtype),
        ', '
    ) AS match_subtypes_present,

    MAX(match_confidence) AS max_match_confidence,

    CASE
        WHEN COUNTIF(is_core_family IS NOT NULL) = 0 THEN NULL
        ELSE LOGICAL_OR(COALESCE(is_core_family, FALSE))
    END AS is_core_family,

    ARRAY_AGG(family_reporting_category IGNORE NULLS ORDER BY source_channel LIMIT 1)[SAFE_OFFSET(0)] AS family_reporting_category,
    ARRAY_AGG(family_exclusion_reason IGNORE NULLS ORDER BY source_channel LIMIT 1)[SAFE_OFFSET(0)] AS family_exclusion_reason,

    SUM(COALESCE(products_in_family, 0)) AS shopify_products_in_family,
    SUM(COALESCE(catalog_products_in_family, 0)) AS shopify_catalog_products_in_family,
    SUM(COALESCE(order_only_sku_products_in_family, 0)) AS shopify_order_only_sku_products_in_family,
    SUM(COALESCE(order_only_name_products_in_family, 0)) AS shopify_order_only_name_products_in_family,

    SUM(COALESCE(observed_product_id_count, 0)) AS etsy_observed_product_id_count,
    SUM(COALESCE(observed_sku_count, 0)) AS etsy_observed_sku_count,

    SUM(COALESCE(lifetime_order_count, 0)) AS etsy_lifetime_order_count,
    SUM(COALESCE(lifetime_order_item_count, 0)) AS etsy_lifetime_order_item_count,
    SUM(COALESCE(lifetime_units_sold, 0)) AS etsy_lifetime_units_sold,

    ROUND(
        SUM(COALESCE(lifetime_item_gross_revenue, 0)),
        2
    ) AS etsy_lifetime_item_gross_revenue,

    MIN(first_sold_date) AS etsy_first_sold_date,
    MAX(last_sold_date) AS etsy_last_sold_date,

    SUM(COALESCE(blank_sku_order_item_count, 0)) AS etsy_blank_sku_order_item_count,
    SUM(COALESCE(digital_order_item_count, 0)) AS etsy_digital_order_item_count,

    ARRAY_AGG(etsy_listing_recency_segment IGNORE NULLS ORDER BY last_sold_date DESC LIMIT 1)[SAFE_OFFSET(0)] AS latest_etsy_listing_recency_segment

FROM bridge
GROUP BY
    cross_channel_product_family_key;