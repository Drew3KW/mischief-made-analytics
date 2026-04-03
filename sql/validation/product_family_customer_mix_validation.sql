-- sql/validation/product_family_customer_mix_validation.sql
-- Purpose:
-- Validation checks for marts.anl_product_family_customer_mix

-- 1) Grain check: one row per product_family_key
SELECT
    product_family_key,
    COUNT(*) AS row_count
FROM `mischief-made-analytics.marts.anl_product_family_customer_mix`
GROUP BY product_family_key
HAVING COUNT(*) > 1;


-- 2) Repeat + one-time customers should equal total family customers
-- This should hold because anl_customer_order_behavior classifies each customer
-- as one_time or repeat, and the model excludes blank customer_email rows.
SELECT
    product_family_key,
    product_family_name,
    customers_who_bought_family,
    one_time_customers_who_bought_family,
    repeat_customers_who_bought_family,
    COALESCE(one_time_customers_who_bought_family, 0)
        + COALESCE(repeat_customers_who_bought_family, 0) AS summed_customer_types
FROM `mischief-made-analytics.marts.anl_product_family_customer_mix`
WHERE COALESCE(one_time_customers_who_bought_family, 0)
    + COALESCE(repeat_customers_who_bought_family, 0)
    != customers_who_bought_family;


-- 3) First-purchase family customers should not exceed total family customers
SELECT
    product_family_key,
    product_family_name,
    customers_first_buying_this_family,
    customers_who_bought_family
FROM `mischief-made-analytics.marts.anl_product_family_customer_mix`
WHERE customers_first_buying_this_family > customers_who_bought_family;


-- 4) Percent fields should be in [0, 1]
SELECT
    product_family_key,
    product_family_name,
    pct_repeat_customers,
    pct_of_family_customers_first_buying_this_family
FROM `mischief-made-analytics.marts.anl_product_family_customer_mix`
WHERE pct_repeat_customers < 0
   OR pct_repeat_customers > 1
   OR pct_of_family_customers_first_buying_this_family < 0
   OR pct_of_family_customers_first_buying_this_family > 1;


-- 5) Every family in the mix view should exist in the shared family dimension
SELECT
    mix.product_family_key
FROM `mischief-made-analytics.marts.anl_product_family_customer_mix` AS mix
LEFT JOIN `mischief-made-analytics.marts.dim_product_families` AS dpf
    ON mix.product_family_key = dpf.product_family_key
WHERE dpf.product_family_key IS NULL;


-- 6) Revenue tieout:
-- mix view revenue should tie to trusted completed-order item revenue
-- for the same included family set
WITH mix AS (
    SELECT
        ROUND(SUM(gross_family_revenue), 2) AS mix_gross_family_revenue
    FROM `mischief-made-analytics.marts.anl_product_family_customer_mix`
),
base AS (
    SELECT
        ROUND(SUM(oi.gross_item_revenue), 2) AS base_gross_item_revenue
    FROM `mischief-made-analytics.marts.fct_order_items` AS oi
    INNER JOIN `mischief-made-analytics.marts.fct_orders` AS o
        ON oi.order_number = o.order_number
    INNER JOIN `mischief-made-analytics.marts.product_family_map` AS pfm
        ON oi.product_key = pfm.product_key
    INNER JOIN `mischief-made-analytics.marts.dim_product_families` AS dpf
        ON pfm.product_family_key = dpf.product_family_key
    WHERE o.customer_email IS NOT NULL
      AND TRIM(o.customer_email) <> ''
      AND o.cancelled_at_ts IS NULL
      AND LOWER(COALESCE(o.financial_status, '')) NOT IN ('voided', 'cancelled')
      AND o.is_suspect_historical_timing = FALSE
      AND dpf.product_family_name IS NOT NULL
      AND TRIM(dpf.product_family_name) <> ''
      AND NOT REGEXP_CONTAINS(
          LOWER(dpf.product_family_name),
          r'\b(mystery boxes?|stickers?|decals?|keychains?|greeting[ -]?cards?|pins?|patches?|magnets?)\b'
      )
)
SELECT
    mix_gross_family_revenue,
    base_gross_item_revenue,
    ROUND(mix_gross_family_revenue - base_gross_item_revenue, 2) AS diff
FROM mix
CROSS JOIN base;


-- 7) Customer count tieout:
-- distinct customers in the mix view should match distinct trusted completed-order
-- customers who bought at least one mapped family
WITH mix AS (
    SELECT
        COUNT(DISTINCT customer_email) AS mix_distinct_customers
    FROM (
        SELECT
            pfm.product_family_key,
            o.customer_email
        FROM `mischief-made-analytics.marts.fct_order_items` AS oi
        INNER JOIN `mischief-made-analytics.marts.fct_orders` AS o
            ON oi.order_number = o.order_number
        INNER JOIN `mischief-made-analytics.marts.product_family_map` AS pfm
            ON oi.product_key = pfm.product_key
        WHERE o.customer_email IS NOT NULL
          AND TRIM(o.customer_email) <> ''
          AND o.cancelled_at_ts IS NULL
          AND LOWER(COALESCE(o.financial_status, '')) NOT IN ('voided', 'cancelled')
          AND o.is_suspect_historical_timing = FALSE
    )
),
base AS (
    SELECT
        COUNT(DISTINCT o.customer_email) AS base_distinct_customers
    FROM `mischief-made-analytics.marts.fct_order_items` AS oi
    INNER JOIN `mischief-made-analytics.marts.fct_orders` AS o
        ON oi.order_number = o.order_number
    INNER JOIN `mischief-made-analytics.marts.product_family_map` AS pfm
        ON oi.product_key = pfm.product_key
    WHERE o.customer_email IS NOT NULL
      AND TRIM(o.customer_email) <> ''
      AND o.cancelled_at_ts IS NULL
      AND LOWER(COALESCE(o.financial_status, '')) NOT IN ('voided', 'cancelled')
      AND o.is_suspect_historical_timing = FALSE
)
SELECT
    mix_distinct_customers,
    base_distinct_customers,
    mix_distinct_customers - base_distinct_customers AS diff
FROM mix
CROSS JOIN base;
