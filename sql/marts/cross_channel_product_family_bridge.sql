-- sql/marts/cross_channel_product_family_bridge.sql
-- Model: marts.cross_channel_product_family_bridge
-- Grain:
-- - One row per Shopify product family.
-- - One row per Etsy listing.
--
-- Purpose:
-- Create a conservative, auditable bridge between Shopify product families
-- and Etsy listings.
--
-- Notes:
-- - Shopify product families map to themselves.
-- - Etsy exact_sku and sku_family matches are accepted.
-- - Etsy title_pattern_match rows are kept as review candidates only.
-- - Etsy unresolved listings remain visible and are not forced into a match.
-- - This marts model does not depend on analysis views.

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.cross_channel_product_family_bridge` AS

WITH shopify_families AS (
    SELECT
        product_family_key,
        product_family_name,
        is_core_family,
        family_reporting_category,
        family_exclusion_reason,
        products_in_family,
        source_types_in_family,
        catalog_products_in_family,
        order_only_sku_products_in_family,
        order_only_name_products_in_family
    FROM `mischief-made-analytics.marts.dim_product_families`
),

etsy_listings AS (
    SELECT
        CAST(listing_id AS STRING) AS listing_id,
        etsy_listing_key,
        latest_listing_title,
        latest_sku,

        LOWER(NULLIF(TRIM(latest_sku), '')) AS normalized_etsy_sku,

        REGEXP_REPLACE(
            LOWER(NULLIF(TRIM(latest_sku), '')),
            r'-(xxs|xs|s|m|l|xl|xxl|2x|2xl|3x|3xl|4x|4xl|5x|5xl|6x|6xl|3xk)$',
            ''
        ) AS normalized_etsy_sku_family,

        REGEXP_REPLACE(
            LOWER(NULLIF(TRIM(latest_listing_title), '')),
            r'[^a-z0-9]+',
            '_'
        ) AS normalized_listing_title_key,

        observed_product_id_count,
        observed_sku_count,
        lifetime_order_count,
        lifetime_order_item_count,
        lifetime_units_sold,
        lifetime_item_gross_revenue,
        first_sold_date,
        last_sold_date,
        blank_sku_order_item_count,
        digital_order_item_count,
        etsy_listing_recency_segment
    FROM `mischief-made-analytics.marts.dim_etsy_listings`
),

shopify_sku_family_candidates AS (
    SELECT
        LOWER(NULLIF(TRIM(sku), '')) AS normalized_shopify_sku,
        product_family_key,
        ANY_VALUE(canonical_product_family_name) AS product_family_name,
        ANY_VALUE(is_core_family) AS is_core_family,
        ANY_VALUE(family_reporting_category) AS family_reporting_category,
        ANY_VALUE(family_exclusion_reason) AS family_exclusion_reason,
        COUNT(DISTINCT product_key) AS shopify_products_with_sku
    FROM `mischief-made-analytics.marts.product_family_map`
    WHERE sku IS NOT NULL
      AND TRIM(sku) != ''
    GROUP BY
        normalized_shopify_sku,
        product_family_key
),

shopify_family_candidates AS (
    SELECT
        product_family_key,
        product_family_name,
        is_core_family,
        family_reporting_category,
        family_exclusion_reason,

        REGEXP_REPLACE(
            LOWER(NULLIF(TRIM(product_family_name), '')),
            r'[^a-z0-9]+',
            '_'
        ) AS normalized_family_name_key
    FROM `mischief-made-analytics.marts.dim_product_families`
    WHERE product_family_name IS NOT NULL
      AND TRIM(product_family_name) != ''
),

sku_exact_candidates AS (
    SELECT
        e.listing_id,
        s.product_family_key AS candidate_product_family_key,
        s.product_family_name AS candidate_product_family_name,
        s.is_core_family AS candidate_is_core_family,
        s.family_reporting_category AS candidate_family_reporting_category,
        s.family_exclusion_reason AS candidate_family_exclusion_reason,
        'sku_match' AS candidate_match_type,
        'exact_sku' AS candidate_match_subtype,
        0.95 AS candidate_match_confidence,
        1 AS candidate_priority
    FROM etsy_listings AS e
    INNER JOIN shopify_sku_family_candidates AS s
        ON e.normalized_etsy_sku = s.normalized_shopify_sku
    WHERE e.normalized_etsy_sku IS NOT NULL
),

sku_family_candidates AS (
    SELECT
        e.listing_id,
        f.product_family_key AS candidate_product_family_key,
        f.product_family_name AS candidate_product_family_name,
        f.is_core_family AS candidate_is_core_family,
        f.family_reporting_category AS candidate_family_reporting_category,
        f.family_exclusion_reason AS candidate_family_exclusion_reason,
        'sku_match' AS candidate_match_type,
        'sku_family' AS candidate_match_subtype,
        0.90 AS candidate_match_confidence,
        2 AS candidate_priority
    FROM etsy_listings AS e
    INNER JOIN shopify_family_candidates AS f
        ON e.normalized_etsy_sku_family = f.product_family_key
    WHERE e.normalized_etsy_sku_family IS NOT NULL
),

title_pattern_candidates AS (
    SELECT
        e.listing_id,
        f.product_family_key AS candidate_product_family_key,
        f.product_family_name AS candidate_product_family_name,
        f.is_core_family AS candidate_is_core_family,
        f.family_reporting_category AS candidate_family_reporting_category,
        f.family_exclusion_reason AS candidate_family_exclusion_reason,
        'title_pattern_match' AS candidate_match_type,
        'family_name_in_listing_title' AS candidate_match_subtype,
        0.65 AS candidate_match_confidence,
        3 AS candidate_priority
    FROM etsy_listings AS e
    INNER JOIN shopify_family_candidates AS f
        ON STRPOS(e.normalized_listing_title_key, f.normalized_family_name_key) > 0
    WHERE e.normalized_listing_title_key IS NOT NULL
      AND f.normalized_family_name_key IS NOT NULL
      AND LENGTH(f.normalized_family_name_key) >= 8
),

all_candidates AS (
    SELECT * FROM sku_exact_candidates
    UNION ALL
    SELECT * FROM sku_family_candidates
    UNION ALL
    SELECT * FROM title_pattern_candidates
),

candidate_counts AS (
    SELECT
        listing_id,
        COUNT(*) AS candidate_count,
        COUNTIF(candidate_priority = 1) AS exact_sku_candidate_count,
        COUNTIF(candidate_priority = 2) AS sku_family_candidate_count,
        COUNTIF(candidate_priority = 3) AS title_pattern_candidate_count
    FROM all_candidates
    GROUP BY
        listing_id
),

ranked_candidates AS (
    SELECT
        c.*,
        ROW_NUMBER() OVER (
            PARTITION BY c.listing_id
            ORDER BY
                c.candidate_priority,
                LENGTH(c.candidate_product_family_name) DESC,
                c.candidate_product_family_key
        ) AS candidate_rank
    FROM all_candidates AS c
),

best_candidates AS (
    SELECT *
    FROM ranked_candidates
    WHERE candidate_rank = 1
),

etsy_listing_audit AS (
    SELECT
        e.listing_id,
        e.etsy_listing_key,
        e.latest_listing_title,
        e.latest_sku,
        e.normalized_etsy_sku,
        e.normalized_etsy_sku_family,

        CASE
            WHEN b.listing_id IS NULL THEN 'unresolved'
            ELSE b.candidate_match_type
        END AS audit_match_type,

        CASE
            WHEN e.normalized_etsy_sku IS NULL THEN 'missing_etsy_sku'
            WHEN b.listing_id IS NULL THEN 'no_candidate_found'
            ELSE 'candidate_found'
        END AS audit_resolution_status,

        b.candidate_match_subtype,
        b.candidate_match_confidence,
        b.candidate_priority,

        b.candidate_product_family_key,
        b.candidate_product_family_name,
        b.candidate_is_core_family,
        b.candidate_family_reporting_category,
        b.candidate_family_exclusion_reason,

        COALESCE(cc.candidate_count, 0) AS candidate_count,
        COALESCE(cc.exact_sku_candidate_count, 0) AS exact_sku_candidate_count,
        COALESCE(cc.sku_family_candidate_count, 0) AS sku_family_candidate_count,
        COALESCE(cc.title_pattern_candidate_count, 0) AS title_pattern_candidate_count,

        e.observed_product_id_count,
        e.observed_sku_count,
        e.lifetime_order_count,
        e.lifetime_order_item_count,
        e.lifetime_units_sold,
        e.lifetime_item_gross_revenue,
        e.first_sold_date,
        e.last_sold_date,
        e.blank_sku_order_item_count,
        e.digital_order_item_count,
        e.etsy_listing_recency_segment
    FROM etsy_listings AS e
    LEFT JOIN best_candidates AS b
        ON e.listing_id = b.listing_id
    LEFT JOIN candidate_counts AS cc
        ON e.listing_id = cc.listing_id
),

shopify_bridge AS (
    SELECT
        CONCAT('product_family:', product_family_key) AS cross_channel_product_family_key,
        'shopify' AS source_channel,
        'shopify_product_family' AS source_entity_type,

        product_family_key AS source_product_family_key,
        CAST(NULL AS STRING) AS source_listing_id,
        CAST(NULL AS STRING) AS source_listing_key,

        product_family_name AS source_product_name,
        CAST(NULL AS STRING) AS source_sku,

        product_family_key AS mapped_product_family_key,
        product_family_name AS mapped_product_family_name,

        product_family_key AS candidate_product_family_key,
        product_family_name AS candidate_product_family_name,

        'shopify_native' AS match_type,
        'shopify_native_family' AS match_subtype,
        1.00 AS match_confidence,
        'accepted' AS bridge_resolution_status,
        TRUE AS is_auto_accepted,

        is_core_family,
        family_reporting_category,
        family_exclusion_reason,

        CAST(NULL AS INT64) AS candidate_count,
        CAST(NULL AS INT64) AS exact_sku_candidate_count,
        CAST(NULL AS INT64) AS sku_family_candidate_count,
        CAST(NULL AS INT64) AS title_pattern_candidate_count,

        products_in_family,
        source_types_in_family,
        catalog_products_in_family,
        order_only_sku_products_in_family,
        order_only_name_products_in_family,

        CAST(NULL AS INT64) AS observed_product_id_count,
        CAST(NULL AS INT64) AS observed_sku_count,
        CAST(NULL AS INT64) AS lifetime_order_count,
        CAST(NULL AS INT64) AS lifetime_order_item_count,
        CAST(NULL AS INT64) AS lifetime_units_sold,
        CAST(NULL AS NUMERIC) AS lifetime_item_gross_revenue,
        CAST(NULL AS DATE) AS first_sold_date,
        CAST(NULL AS DATE) AS last_sold_date,
        CAST(NULL AS INT64) AS blank_sku_order_item_count,
        CAST(NULL AS INT64) AS digital_order_item_count,
        CAST(NULL AS STRING) AS etsy_listing_recency_segment
    FROM shopify_families
),

etsy_bridge AS (
    SELECT
        CASE
            WHEN audit_match_type = 'sku_match'
              AND candidate_match_subtype IN ('exact_sku', 'sku_family')
                THEN CONCAT('product_family:', candidate_product_family_key)
            ELSE CONCAT('etsy_listing:', listing_id)
        END AS cross_channel_product_family_key,

        'etsy' AS source_channel,
        'etsy_listing' AS source_entity_type,

        CAST(NULL AS STRING) AS source_product_family_key,
        listing_id AS source_listing_id,
        etsy_listing_key AS source_listing_key,

        latest_listing_title AS source_product_name,
        latest_sku AS source_sku,

        CASE
            WHEN audit_match_type = 'sku_match'
              AND candidate_match_subtype IN ('exact_sku', 'sku_family')
                THEN candidate_product_family_key
            ELSE NULL
        END AS mapped_product_family_key,

        CASE
            WHEN audit_match_type = 'sku_match'
              AND candidate_match_subtype IN ('exact_sku', 'sku_family')
                THEN candidate_product_family_name
            ELSE NULL
        END AS mapped_product_family_name,

        candidate_product_family_key,
        candidate_product_family_name,

        audit_match_type AS match_type,
        candidate_match_subtype AS match_subtype,
        candidate_match_confidence AS match_confidence,

        CASE
            WHEN audit_match_type = 'sku_match'
              AND candidate_match_subtype IN ('exact_sku', 'sku_family')
                THEN 'accepted'
            WHEN audit_match_type = 'title_pattern_match'
                THEN 'review_candidate'
            ELSE 'unresolved'
        END AS bridge_resolution_status,

        CASE
            WHEN audit_match_type = 'sku_match'
              AND candidate_match_subtype IN ('exact_sku', 'sku_family')
                THEN TRUE
            ELSE FALSE
        END AS is_auto_accepted,

        CASE
            WHEN audit_match_type = 'sku_match'
              AND candidate_match_subtype IN ('exact_sku', 'sku_family')
                THEN candidate_is_core_family
            ELSE NULL
        END AS is_core_family,

        CASE
            WHEN audit_match_type = 'sku_match'
              AND candidate_match_subtype IN ('exact_sku', 'sku_family')
                THEN candidate_family_reporting_category
            ELSE NULL
        END AS family_reporting_category,

        CASE
            WHEN audit_match_type = 'sku_match'
              AND candidate_match_subtype IN ('exact_sku', 'sku_family')
                THEN candidate_family_exclusion_reason
            ELSE NULL
        END AS family_exclusion_reason,

        candidate_count,
        exact_sku_candidate_count,
        sku_family_candidate_count,
        title_pattern_candidate_count,

        CAST(NULL AS INT64) AS products_in_family,
        CAST(NULL AS INT64) AS source_types_in_family,
        CAST(NULL AS INT64) AS catalog_products_in_family,
        CAST(NULL AS INT64) AS order_only_sku_products_in_family,
        CAST(NULL AS INT64) AS order_only_name_products_in_family,

        observed_product_id_count,
        observed_sku_count,
        lifetime_order_count,
        lifetime_order_item_count,
        lifetime_units_sold,
        CAST(lifetime_item_gross_revenue AS NUMERIC) AS lifetime_item_gross_revenue,
        first_sold_date,
        last_sold_date,
        blank_sku_order_item_count,
        digital_order_item_count,
        etsy_listing_recency_segment
    FROM etsy_listing_audit
)

SELECT * FROM shopify_bridge
UNION ALL
SELECT * FROM etsy_bridge;