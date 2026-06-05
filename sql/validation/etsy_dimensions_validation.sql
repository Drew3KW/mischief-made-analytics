-- sql/validation/etsy_dimensions_validation.sql
-- Purpose:
-- Validate Etsy-native dimension models for Milestone 49.
--
-- Scope:
-- - marts.dim_etsy_customers
-- - marts.dim_etsy_listings
--
-- Notes:
-- - These dimensions are Etsy-only.
-- - Cross-channel customer identity resolution is deferred.
-- - Cross-channel product/listing harmonization is deferred.

WITH customers AS (
    SELECT *
    FROM `mischief-made-analytics.marts.dim_etsy_customers`
),

listings AS (
    SELECT *
    FROM `mischief-made-analytics.marts.dim_etsy_listings`
),

orders AS (
    SELECT *
    FROM `mischief-made-analytics.marts.fct_etsy_orders`
),

order_items AS (
    SELECT *
    FROM `mischief-made-analytics.marts.fct_etsy_order_items`
),

customer_shape AS (
    SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT buyer_user_id) AS distinct_buyer_user_id_count,
        COUNTIF(buyer_user_id IS NULL) AS null_buyer_user_id_count,
        COUNTIF(etsy_buyer_key IS NULL OR TRIM(etsy_buyer_key) = '') AS null_etsy_buyer_key_count,
        COUNTIF(first_order_date IS NULL) AS null_first_order_date_count,
        COUNTIF(last_order_date IS NULL) AS null_last_order_date_count,
        COUNTIF(first_order_date > last_order_date) AS invalid_customer_date_order_count,
        COUNTIF(lifetime_order_count < 1) AS invalid_lifetime_order_count,
        COUNTIF(lifetime_items_purchased < 0) AS negative_lifetime_items_count,
        COUNTIF(lifetime_gross_revenue < 0) AS negative_lifetime_gross_revenue_count,
        COUNTIF(etsy_customer_type NOT IN ('one_time', 'repeat', 'loyal')) AS invalid_customer_type_count,
        COUNTIF(etsy_recency_segment NOT IN ('active_recent', 'warm', 'cooling_off', 'lapsed')) AS invalid_recency_segment_count
    FROM customers
),

listing_shape AS (
    SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT listing_id) AS distinct_listing_id_count,
        COUNTIF(listing_id IS NULL) AS null_listing_id_count,
        COUNTIF(etsy_listing_key IS NULL OR TRIM(etsy_listing_key) = '') AS null_etsy_listing_key_count,
        COUNTIF(first_sold_date IS NULL) AS null_first_sold_date_count,
        COUNTIF(last_sold_date IS NULL) AS null_last_sold_date_count,
        COUNTIF(first_sold_date > last_sold_date) AS invalid_listing_date_order_count,
        COUNTIF(lifetime_order_count < 1) AS invalid_lifetime_order_count,
        COUNTIF(lifetime_order_item_count < 1) AS invalid_lifetime_order_item_count,
        COUNTIF(lifetime_units_sold < 0) AS negative_lifetime_units_count,
        COUNTIF(lifetime_item_gross_revenue < 0) AS negative_lifetime_item_gross_revenue_count,
        COUNTIF(etsy_listing_recency_segment NOT IN ('active_recent', 'warm', 'cooling_off', 'lapsed')) AS invalid_listing_recency_segment_count
    FROM listings
),

customer_fact_integrity AS (
    SELECT
        COUNT(DISTINCT o.buyer_user_id) AS buyer_user_ids_in_orders,
        COUNT(DISTINCT c.buyer_user_id) AS buyer_user_ids_in_dimension,
        COUNT(DISTINCT CASE
            WHEN c.buyer_user_id IS NULL THEN o.buyer_user_id
        END) AS missing_customer_dimension_count
    FROM orders AS o
    LEFT JOIN customers AS c
        ON o.buyer_user_id = c.buyer_user_id
    WHERE o.buyer_user_id IS NOT NULL
),

listing_fact_integrity AS (
    SELECT
        COUNT(DISTINCT oi.listing_id) AS listing_ids_in_order_items,
        COUNT(DISTINCT l.listing_id) AS listing_ids_in_dimension,
        COUNT(DISTINCT CASE
            WHEN l.listing_id IS NULL THEN oi.listing_id
        END) AS missing_listing_dimension_count
    FROM order_items AS oi
    LEFT JOIN listings AS l
        ON oi.listing_id = l.listing_id
    WHERE oi.listing_id IS NOT NULL
),

customer_rollup AS (
    SELECT
        buyer_user_id,
        COUNT(DISTINCT receipt_id) AS lifetime_order_count,
        SUM(COALESCE(total_items, 0)) AS lifetime_items_purchased,
        ROUND(SUM(COALESCE(receipt_gross_amount, 0)), 2) AS lifetime_gross_revenue
    FROM orders
    WHERE buyer_user_id IS NOT NULL
    GROUP BY buyer_user_id
),

customer_rollup_vs_dimension AS (
    SELECT
        COUNT(*) AS compared_customer_count,

        COUNTIF(
            COALESCE(c.lifetime_order_count, -1)
                != COALESCE(r.lifetime_order_count, -2)
        ) AS lifetime_order_count_mismatches,

        COUNTIF(
            COALESCE(c.lifetime_items_purchased, -1)
                != COALESCE(r.lifetime_items_purchased, -2)
        ) AS lifetime_items_purchased_mismatches,

        COUNTIF(
            COALESCE(ROUND(c.lifetime_gross_revenue, 2), -1)
                != COALESCE(r.lifetime_gross_revenue, -2)
        ) AS lifetime_gross_revenue_mismatches

    FROM customers AS c
    LEFT JOIN customer_rollup AS r
        ON c.buyer_user_id = r.buyer_user_id
),

listing_rollup AS (
    SELECT
        listing_id,
        COUNT(DISTINCT receipt_id) AS lifetime_order_count,
        COUNT(DISTINCT transaction_id) AS lifetime_order_item_count,
        SUM(COALESCE(quantity, 0)) AS lifetime_units_sold,
        ROUND(SUM(COALESCE(item_gross_amount, 0)), 2) AS lifetime_item_gross_revenue
    FROM order_items
    WHERE listing_id IS NOT NULL
    GROUP BY listing_id
),

listing_rollup_vs_dimension AS (
    SELECT
        COUNT(*) AS compared_listing_count,

        COUNTIF(
            COALESCE(l.lifetime_order_count, -1)
                != COALESCE(r.lifetime_order_count, -2)
        ) AS lifetime_order_count_mismatches,

        COUNTIF(
            COALESCE(l.lifetime_order_item_count, -1)
                != COALESCE(r.lifetime_order_item_count, -2)
        ) AS lifetime_order_item_count_mismatches,

        COUNTIF(
            COALESCE(l.lifetime_units_sold, -1)
                != COALESCE(r.lifetime_units_sold, -2)
        ) AS lifetime_units_sold_mismatches,

        COUNTIF(
            COALESCE(ROUND(l.lifetime_item_gross_revenue, 2), -1)
                != COALESCE(r.lifetime_item_gross_revenue, -2)
        ) AS lifetime_item_gross_revenue_mismatches

    FROM listings AS l
    LEFT JOIN listing_rollup AS r
        ON l.listing_id = r.listing_id
),

validation_results AS (
    SELECT
        'dim_etsy_customers_row_count' AS check_name,
        CAST(row_count AS STRING) AS result_value,
        '> 0' AS expected_value,
        CASE WHEN row_count > 0 THEN 'PASS' ELSE 'FAIL' END AS check_status,
        'Etsy customer dimension should contain rows.' AS notes
    FROM customer_shape

    UNION ALL

    SELECT
        'dim_etsy_customers_duplicate_key_count',
        CAST(row_count - distinct_buyer_user_id_count AS STRING),
        '0',
        CASE WHEN row_count - distinct_buyer_user_id_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Etsy customer dimension should have one row per buyer_user_id.'
    FROM customer_shape

    UNION ALL

    SELECT
        'dim_etsy_customers_null_key_count',
        CAST(null_buyer_user_id_count + null_etsy_buyer_key_count AS STRING),
        '0',
        CASE
            WHEN null_buyer_user_id_count + null_etsy_buyer_key_count = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Etsy customer dimension keys should not be null.'
    FROM customer_shape

    UNION ALL

    SELECT
        'dim_etsy_customers_invalid_date_count',
        CAST(
            null_first_order_date_count
            + null_last_order_date_count
            + invalid_customer_date_order_count
            AS STRING
        ),
        '0',
        CASE
            WHEN null_first_order_date_count
                + null_last_order_date_count
                + invalid_customer_date_order_count = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Etsy customer first/last order dates should be populated and ordered correctly.'
    FROM customer_shape

    UNION ALL

    SELECT
        'dim_etsy_customers_invalid_count_or_money_count',
        CAST(
            invalid_lifetime_order_count
            + negative_lifetime_items_count
            + negative_lifetime_gross_revenue_count
            AS STRING
        ),
        '0',
        CASE
            WHEN invalid_lifetime_order_count
                + negative_lifetime_items_count
                + negative_lifetime_gross_revenue_count = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Etsy customer lifetime counts and revenue should be valid.'
    FROM customer_shape

    UNION ALL

    SELECT
        'dim_etsy_customers_invalid_segment_count',
        CAST(invalid_customer_type_count + invalid_recency_segment_count AS STRING),
        '0',
        CASE
            WHEN invalid_customer_type_count + invalid_recency_segment_count = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Etsy customer type and recency segment should use expected values.'
    FROM customer_shape

    UNION ALL

    SELECT
        'dim_etsy_customers_fact_integrity',
        CAST(missing_customer_dimension_count AS STRING),
        '0',
        CASE WHEN missing_customer_dimension_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Every non-null buyer_user_id in fct_etsy_orders should appear in dim_etsy_customers.'
    FROM customer_fact_integrity

    UNION ALL

    SELECT
        'dim_etsy_customers_rollup_vs_orders',
        CAST(
            lifetime_order_count_mismatches
            + lifetime_items_purchased_mismatches
            + lifetime_gross_revenue_mismatches
            AS STRING
        ),
        '0',
        CASE
            WHEN lifetime_order_count_mismatches
                + lifetime_items_purchased_mismatches
                + lifetime_gross_revenue_mismatches = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Customer dimension lifetime rollups should tie to fct_etsy_orders.'
    FROM customer_rollup_vs_dimension

    UNION ALL

    SELECT
        'dim_etsy_listings_row_count',
        CAST(row_count AS STRING),
        '> 0',
        CASE WHEN row_count > 0 THEN 'PASS' ELSE 'FAIL' END,
        'Etsy listing dimension should contain rows.'
    FROM listing_shape

    UNION ALL

    SELECT
        'dim_etsy_listings_duplicate_key_count',
        CAST(row_count - distinct_listing_id_count AS STRING),
        '0',
        CASE WHEN row_count - distinct_listing_id_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Etsy listing dimension should have one row per listing_id.'
    FROM listing_shape

    UNION ALL

    SELECT
        'dim_etsy_listings_null_key_count',
        CAST(null_listing_id_count + null_etsy_listing_key_count AS STRING),
        '0',
        CASE
            WHEN null_listing_id_count + null_etsy_listing_key_count = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Etsy listing dimension keys should not be null.'
    FROM listing_shape

    UNION ALL

    SELECT
        'dim_etsy_listings_invalid_date_count',
        CAST(
            null_first_sold_date_count
            + null_last_sold_date_count
            + invalid_listing_date_order_count
            AS STRING
        ),
        '0',
        CASE
            WHEN null_first_sold_date_count
                + null_last_sold_date_count
                + invalid_listing_date_order_count = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Etsy listing first/last sold dates should be populated and ordered correctly.'
    FROM listing_shape

    UNION ALL

    SELECT
        'dim_etsy_listings_invalid_count_or_money_count',
        CAST(
            invalid_lifetime_order_count
            + invalid_lifetime_order_item_count
            + negative_lifetime_units_count
            + negative_lifetime_item_gross_revenue_count
            AS STRING
        ),
        '0',
        CASE
            WHEN invalid_lifetime_order_count
                + invalid_lifetime_order_item_count
                + negative_lifetime_units_count
                + negative_lifetime_item_gross_revenue_count = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Etsy listing lifetime counts and revenue should be valid.'
    FROM listing_shape

    UNION ALL

    SELECT
        'dim_etsy_listings_invalid_recency_segment_count',
        CAST(invalid_listing_recency_segment_count AS STRING),
        '0',
        CASE WHEN invalid_listing_recency_segment_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Etsy listing recency segment should use expected values.'
    FROM listing_shape

    UNION ALL

    SELECT
        'dim_etsy_listings_fact_integrity',
        CAST(missing_listing_dimension_count AS STRING),
        '0',
        CASE WHEN missing_listing_dimension_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Every non-null listing_id in fct_etsy_order_items should appear in dim_etsy_listings.'
    FROM listing_fact_integrity

    UNION ALL

    SELECT
        'dim_etsy_listings_rollup_vs_order_items',
        CAST(
            lifetime_order_count_mismatches
            + lifetime_order_item_count_mismatches
            + lifetime_units_sold_mismatches
            + lifetime_item_gross_revenue_mismatches
            AS STRING
        ),
        '0',
        CASE
            WHEN lifetime_order_count_mismatches
                + lifetime_order_item_count_mismatches
                + lifetime_units_sold_mismatches
                + lifetime_item_gross_revenue_mismatches = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END,
        'Listing dimension lifetime rollups should tie to fct_etsy_order_items.'
    FROM listing_rollup_vs_dimension
)

SELECT
    check_name,
    result_value,
    expected_value,
    check_status,
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
    check_name;