-- sql/validation/cross_channel_identity_hardening_validation.sql
-- Purpose:
-- Validate Milestone 50 cross-channel customer and product-family hardening.
--
-- Scope:
-- - marts.cross_channel_customer_bridge
-- - marts.cross_channel_product_family_bridge
-- - marts.dim_cross_channel_customers
-- - marts.dim_cross_channel_product_families
--
-- Notes:
-- - Etsy buyer email is currently unavailable from the Etsy API response.
-- - Etsy customer identities therefore remain unresolved by design.
-- - Etsy title-pattern product matches remain review candidates by design.
-- - Unresolved customer and product rows remain visible by design.

WITH customer_bridge AS (
    SELECT *
    FROM `mischief-made-analytics.marts.cross_channel_customer_bridge`
),

product_bridge AS (
    SELECT *
    FROM `mischief-made-analytics.marts.cross_channel_product_family_bridge`
),

customer_dim AS (
    SELECT *
    FROM `mischief-made-analytics.marts.dim_cross_channel_customers`
),

product_dim AS (
    SELECT *
    FROM `mischief-made-analytics.marts.dim_cross_channel_product_families`
),

customer_bridge_source_duplicates AS (
    SELECT
        source_channel,
        source_entity_type,
        source_customer_key,
        COUNT(*) AS row_count
    FROM customer_bridge
    GROUP BY
        source_channel,
        source_entity_type,
        source_customer_key
    HAVING COUNT(*) > 1
),

product_bridge_source_duplicates AS (
    SELECT
        source_channel,
        source_entity_type,
        COALESCE(source_product_family_key, source_listing_id) AS source_product_key,
        COUNT(*) AS row_count
    FROM product_bridge
    GROUP BY
        source_channel,
        source_entity_type,
        source_product_key
    HAVING COUNT(*) > 1
),

customer_source_counts AS (
    SELECT
        'shopify' AS source_channel,
        COUNT(*) AS source_rows
    FROM `mischief-made-analytics.marts.dim_customers`
    WHERE customer_email IS NOT NULL
      AND TRIM(customer_email) != ''

    UNION ALL

    SELECT
        'etsy' AS source_channel,
        COUNT(*) AS source_rows
    FROM `mischief-made-analytics.marts.dim_etsy_customers`
    WHERE buyer_user_id IS NOT NULL
),

customer_bridge_counts AS (
    SELECT
        source_channel,
        COUNT(*) AS bridge_rows
    FROM customer_bridge
    GROUP BY
        source_channel
),

product_source_counts AS (
    SELECT
        'shopify' AS source_channel,
        COUNT(*) AS source_rows
    FROM `mischief-made-analytics.marts.dim_product_families`

    UNION ALL

    SELECT
        'etsy' AS source_channel,
        COUNT(*) AS source_rows
    FROM `mischief-made-analytics.marts.dim_etsy_listings`
),

product_bridge_counts AS (
    SELECT
        source_channel,
        COUNT(*) AS bridge_rows
    FROM product_bridge
    GROUP BY
        source_channel
),

customer_dim_duplicate_keys AS (
    SELECT
        cross_channel_customer_key,
        COUNT(*) AS row_count
    FROM customer_dim
    GROUP BY
        cross_channel_customer_key
    HAVING COUNT(*) > 1
),

product_dim_duplicate_keys AS (
    SELECT
        cross_channel_product_family_key,
        COUNT(*) AS row_count
    FROM product_dim
    GROUP BY
        cross_channel_product_family_key
    HAVING COUNT(*) > 1
),

etsy_buyer_email_diagnostic AS (
    SELECT
        COUNT(*) AS receipt_rows,
        COUNTIF(buyer_email IS NOT NULL AND TRIM(buyer_email) != '') AS populated_buyer_email_rows,
        COUNTIF(REGEXP_CONTAINS(raw_json, r'"buyer_email"')) AS raw_json_has_buyer_email_key_rows,
        COUNTIF(REGEXP_CONTAINS(raw_json, r'"buyer_email"\s*:\s*null')) AS raw_json_buyer_email_explicit_null_rows
    FROM `mischief-made-analytics.raw_load.etsy_receipts_api_latest`
),

validation_results AS (
    SELECT
        'customer_bridge' AS check_area,
        'customer_bridge_source_grain_unique' AS check_name,
        IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNT(*) AS STRING) AS observed_value,
        '0 duplicate source keys' AS expected_value,
        'Customer bridge should have no duplicate source customer rows.' AS notes
    FROM customer_bridge_source_duplicates

    UNION ALL

    SELECT
        'product_bridge' AS check_area,
        'product_bridge_source_grain_unique' AS check_name,
        IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNT(*) AS STRING) AS observed_value,
        '0 duplicate source keys' AS expected_value,
        'Product bridge should have no duplicate source product-family or listing rows.' AS notes
    FROM product_bridge_source_duplicates

    UNION ALL

    SELECT
        'customer_bridge' AS check_area,
        'customer_bridge_expected_match_types' AS check_name,
        IF(COUNTIF(match_type NOT IN ('exact_email', 'manual_match', 'channel_only', 'unresolved')) = 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNTIF(match_type NOT IN ('exact_email', 'manual_match', 'channel_only', 'unresolved')) AS STRING) AS observed_value,
        '0 unexpected match types' AS expected_value,
        'Customer bridge match types should stay within the approved Milestone 50 values.' AS notes
    FROM customer_bridge

    UNION ALL

    SELECT
        'customer_bridge' AS check_area,
        'customer_bridge_expected_resolution_statuses' AS check_name,
        IF(COUNTIF(bridge_resolution_status NOT IN ('accepted', 'channel_only', 'unresolved')) = 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNTIF(bridge_resolution_status NOT IN ('accepted', 'channel_only', 'unresolved')) AS STRING) AS observed_value,
        '0 unexpected resolution statuses' AS expected_value,
        'Customer bridge resolution statuses should stay within the approved values.' AS notes
    FROM customer_bridge

    UNION ALL

    SELECT
        'product_bridge' AS check_area,
        'product_bridge_expected_match_types' AS check_name,
        IF(COUNTIF(match_type NOT IN ('shopify_native', 'sku_match', 'title_pattern_match', 'unresolved')) = 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNTIF(match_type NOT IN ('shopify_native', 'sku_match', 'title_pattern_match', 'unresolved')) AS STRING) AS observed_value,
        '0 unexpected match types' AS expected_value,
        'Product bridge match types should stay within the approved Milestone 50 values.' AS notes
    FROM product_bridge

    UNION ALL

    SELECT
        'product_bridge' AS check_area,
        'product_bridge_expected_resolution_statuses' AS check_name,
        IF(COUNTIF(bridge_resolution_status NOT IN ('accepted', 'review_candidate', 'unresolved')) = 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNTIF(bridge_resolution_status NOT IN ('accepted', 'review_candidate', 'unresolved')) AS STRING) AS observed_value,
        '0 unexpected resolution statuses' AS expected_value,
        'Product bridge resolution statuses should keep accepted, review, and unresolved cases explicit.' AS notes
    FROM product_bridge

    UNION ALL

    SELECT
        'product_bridge' AS check_area,
        'accepted_etsy_product_rows_have_mapped_family' AS check_name,
        IF(
            COUNTIF(
                source_channel = 'etsy'
                AND bridge_resolution_status = 'accepted'
                AND mapped_product_family_key IS NULL
            ) = 0,
            'PASS',
            'FAIL'
        ) AS check_status,
        CAST(
            COUNTIF(
                source_channel = 'etsy'
                AND bridge_resolution_status = 'accepted'
                AND mapped_product_family_key IS NULL
            ) AS STRING
        ) AS observed_value,
        '0 accepted Etsy rows without mapped family key' AS expected_value,
        'Accepted Etsy listing rows must map to a Shopify product-family key.' AS notes
    FROM product_bridge

    UNION ALL

    SELECT
        'customer_bridge' AS check_area,
        'customer_bridge_ties_to_source_dimensions' AS check_name,
        IF(COUNTIF(s.source_rows != b.bridge_rows) = 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNTIF(s.source_rows != b.bridge_rows) AS STRING) AS observed_value,
        '0 source count differences' AS expected_value,
        'Customer bridge row counts should tie back to Shopify and Etsy source customer dimensions.' AS notes
    FROM customer_source_counts AS s
    LEFT JOIN customer_bridge_counts AS b
        ON s.source_channel = b.source_channel

    UNION ALL

    SELECT
        'product_bridge' AS check_area,
        'product_bridge_ties_to_source_dimensions' AS check_name,
        IF(COUNTIF(s.source_rows != b.bridge_rows) = 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNTIF(s.source_rows != b.bridge_rows) AS STRING) AS observed_value,
        '0 source count differences' AS expected_value,
        'Product bridge row counts should tie back to Shopify product families and Etsy listings.' AS notes
    FROM product_source_counts AS s
    LEFT JOIN product_bridge_counts AS b
        ON s.source_channel = b.source_channel

    UNION ALL

    SELECT
        'customer_dimension' AS check_area,
        'customer_dimension_key_unique' AS check_name,
        IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNT(*) AS STRING) AS observed_value,
        '0 duplicate cross-channel customer keys' AS expected_value,
        'Cross-channel customer dimension should have one row per cross_channel_customer_key.' AS notes
    FROM customer_dim_duplicate_keys

    UNION ALL

    SELECT
        'product_dimension' AS check_area,
        'product_dimension_key_unique' AS check_name,
        IF(COUNT(*) = 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNT(*) AS STRING) AS observed_value,
        '0 duplicate cross-channel product-family keys' AS expected_value,
        'Cross-channel product-family dimension should have one row per cross_channel_product_family_key.' AS notes
    FROM product_dim_duplicate_keys

    UNION ALL

    SELECT
        'customer_dimension' AS check_area,
        'customer_dimension_matches_distinct_bridge_keys' AS check_name,
        IF(
            (SELECT COUNT(*) FROM customer_dim)
            =
            (SELECT COUNT(DISTINCT cross_channel_customer_key) FROM customer_bridge),
            'PASS',
            'FAIL'
        ) AS check_status,
        CAST((SELECT COUNT(*) FROM customer_dim) AS STRING) AS observed_value,
        CAST((SELECT COUNT(DISTINCT cross_channel_customer_key) FROM customer_bridge) AS STRING) AS expected_value,
        'Customer dimension rows should match distinct bridge keys.' AS notes

    UNION ALL

    SELECT
        'product_dimension' AS check_area,
        'product_dimension_matches_distinct_bridge_keys' AS check_name,
        IF(
            (SELECT COUNT(*) FROM product_dim)
            =
            (SELECT COUNT(DISTINCT cross_channel_product_family_key) FROM product_bridge),
            'PASS',
            'FAIL'
        ) AS check_status,
        CAST((SELECT COUNT(*) FROM product_dim) AS STRING) AS observed_value,
        CAST((SELECT COUNT(DISTINCT cross_channel_product_family_key) FROM product_bridge) AS STRING) AS expected_value,
        'Product-family dimension rows should match distinct bridge keys.' AS notes

    UNION ALL

    SELECT
        'customer_dimension' AS check_area,
        'customer_dimension_expected_statuses' AS check_name,
        IF(
            COUNTIF(customer_identity_status NOT IN (
                'cross_channel_matched',
                'shopify_channel_only',
                'etsy_unresolved',
                'review'
            )) = 0,
            'PASS',
            'FAIL'
        ) AS check_status,
        CAST(
            COUNTIF(customer_identity_status NOT IN (
                'cross_channel_matched',
                'shopify_channel_only',
                'etsy_unresolved',
                'review'
            )) AS STRING
        ) AS observed_value,
        '0 unexpected customer identity statuses' AS expected_value,
        'Customer identity statuses should stay within the approved values.' AS notes
    FROM customer_dim

    UNION ALL

    SELECT
        'product_dimension' AS check_area,
        'product_dimension_expected_statuses' AS check_name,
        IF(
            COUNTIF(product_family_identity_status NOT IN (
                'cross_channel_accepted',
                'shopify_only',
                'etsy_review_candidate',
                'etsy_unresolved',
                'review'
            )) = 0,
            'PASS',
            'FAIL'
        ) AS check_status,
        CAST(
            COUNTIF(product_family_identity_status NOT IN (
                'cross_channel_accepted',
                'shopify_only',
                'etsy_review_candidate',
                'etsy_unresolved',
                'review'
            )) AS STRING
        ) AS observed_value,
        '0 unexpected product-family identity statuses' AS expected_value,
        'Product-family identity statuses should stay within the approved values.' AS notes
    FROM product_dim

    UNION ALL

    SELECT
        'customer_dimension' AS check_area,
        'etsy_unresolved_customers_visible' AS check_name,
        IF(COUNTIF(customer_identity_status = 'etsy_unresolved') > 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNTIF(customer_identity_status = 'etsy_unresolved') AS STRING) AS observed_value,
        'greater than 0' AS expected_value,
        'Etsy customers without usable email should remain visible as unresolved.' AS notes
    FROM customer_dim

    UNION ALL

    SELECT
        'product_dimension' AS check_area,
        'etsy_review_candidates_visible' AS check_name,
        IF(COUNTIF(product_family_identity_status = 'etsy_review_candidate') > 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNTIF(product_family_identity_status = 'etsy_review_candidate') AS STRING) AS observed_value,
        'greater than 0' AS expected_value,
        'Etsy title-pattern product candidates should remain visible for review.' AS notes
    FROM product_dim

    UNION ALL

    SELECT
        'product_dimension' AS check_area,
        'etsy_unresolved_product_families_visible' AS check_name,
        IF(COUNTIF(product_family_identity_status = 'etsy_unresolved') > 0, 'PASS', 'FAIL') AS check_status,
        CAST(COUNTIF(product_family_identity_status = 'etsy_unresolved') AS STRING) AS observed_value,
        'greater than 0' AS expected_value,
        'Unresolved Etsy listings should remain visible rather than being forced into product families.' AS notes
    FROM product_dim

    UNION ALL

    SELECT
        'etsy_source_behavior' AS check_area,
        'etsy_buyer_email_unavailable_from_api' AS check_name,
        'INFO' AS check_status,
        CONCAT(
            'receipt_rows=',
            CAST(receipt_rows AS STRING),
            ', populated_buyer_email_rows=',
            CAST(populated_buyer_email_rows AS STRING),
            ', raw_json_has_buyer_email_key_rows=',
            CAST(raw_json_has_buyer_email_key_rows AS STRING),
            ', raw_json_buyer_email_explicit_null_rows=',
            CAST(raw_json_buyer_email_explicit_null_rows AS STRING)
        ) AS observed_value,
        'buyer_email key present but values currently null' AS expected_value,
        'Current Etsy receipt API responses include buyer_email as a JSON key but return null values, so exact-email customer matching is unavailable.' AS notes
    FROM etsy_buyer_email_diagnostic
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
        WHEN 'REVIEW' THEN 2
        WHEN 'INFO' THEN 3
        WHEN 'PASS' THEN 4
        ELSE 5
    END,
    check_area,
    check_name;