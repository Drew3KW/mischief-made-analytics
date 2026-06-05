-- sql/analysis/cross_channel_product_family_mapping_audit.sql
-- Purpose:
-- Audit conservative cross-channel product-family match candidates across
-- Shopify product families and Etsy listings.
--
-- Grain:
-- One row per Etsy listing.
--
-- Notes:
-- - This is an audit view, not the final bridge model.
-- - SKU-based candidates are stronger than title-pattern candidates.
-- - Title-pattern candidates are only candidates for review.
-- - Unresolved Etsy listings remain visible by design.

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_cross_channel_product_family_mapping_audit` AS

WITH etsy_listings AS (
    SELECT
        CAST(listing_id AS STRING) AS listing_id,
        etsy_listing_key,
        latest_listing_title,
        latest_listing_description,
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
    GROUP BY listing_id
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
)

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
    ON e.listing_id = cc.listing_id;