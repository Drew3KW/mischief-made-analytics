-- sql/analysis/product_family_customer_mix.sql
-- Purpose:
-- Business-facing product-family customer mix view for Analysis Pack v1.
--
-- Grain:
-- One row per product_family_key.
--
-- Notes:
-- - Uses trusted dates by default
-- - Uses shared family models from marts.product_family_map and marts.dim_product_families
-- - Excludes cancelled / voided orders
-- - Excludes suspect historical timing rows
-- - Filters to core families via shared upstream family metadata
-- - Connects product-family analysis with customer behavior analysis

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_product_family_customer_mix` AS

WITH trusted_line_base AS (
    SELECT
        oi.order_item_key,
        oi.order_number,
        oi.product_key,
        o.customer_email,
        o.created_at_ts,
        DATE(o.created_at_ts) AS order_date,
        oi.quantity,
        oi.gross_item_revenue,
        oi.net_item_revenue_before_refunds
    FROM `mischief-made-analytics.marts.fct_order_items` AS oi
    INNER JOIN `mischief-made-analytics.marts.fct_orders` AS o
        ON oi.order_number = o.order_number
    WHERE o.customer_email IS NOT NULL
      AND TRIM(o.customer_email) <> ''
      AND o.cancelled_at_ts IS NULL
      AND LOWER(COALESCE(o.financial_status, '')) NOT IN ('voided', 'cancelled')
      AND o.is_suspect_historical_timing = FALSE
),

joined AS (
    SELECT
        tlb.order_item_key,
        tlb.order_number,
        tlb.customer_email,
        tlb.created_at_ts,
        tlb.order_date,
        pfm.product_family_key,
        dpf.product_family_name,
        tlb.quantity,
        tlb.gross_item_revenue,
        tlb.net_item_revenue_before_refunds
    FROM trusted_line_base AS tlb
    INNER JOIN `mischief-made-analytics.marts.product_family_map` AS pfm
        ON tlb.product_key = pfm.product_key
    LEFT JOIN `mischief-made-analytics.marts.dim_product_families` AS dpf
        ON pfm.product_family_key = dpf.product_family_key
    WHERE pfm.product_family_key IS NOT NULL
      AND dpf.product_family_name IS NOT NULL
      AND TRIM(dpf.product_family_name) <> ''
      AND dpf.is_core_family = TRUE
),

family_rollup AS (
    SELECT
        j.product_family_key,
        ANY_VALUE(j.product_family_name) AS product_family_name,
        COUNT(DISTINCT j.customer_email) AS customers_who_bought_family,
        COUNT(DISTINCT j.order_number) AS orders_containing_family,
        SUM(j.quantity) AS units_sold,
        ROUND(SUM(j.gross_item_revenue), 2) AS gross_family_revenue,
        ROUND(SUM(j.net_item_revenue_before_refunds), 2) AS net_family_revenue_before_refunds
    FROM joined AS j
    GROUP BY j.product_family_key
),

family_customer_base AS (
    SELECT DISTINCT
        j.product_family_key,
        j.customer_email
    FROM joined AS j
),

family_customer_metrics AS (
    SELECT
        fcb.product_family_key,
        COUNT(DISTINCT CASE
            WHEN cob.customer_type = 'one_time' THEN fcb.customer_email
        END) AS one_time_customers_who_bought_family,
        COUNT(DISTINCT CASE
            WHEN cob.customer_type = 'repeat' THEN fcb.customer_email
        END) AS repeat_customers_who_bought_family,
        ROUND(AVG(cob.lifetime_revenue), 2) AS avg_customer_lifetime_revenue,
        ROUND(AVG(cob.lifetime_orders), 2) AS avg_customer_lifetime_orders
    FROM family_customer_base AS fcb
    LEFT JOIN `mischief-made-analytics.marts.anl_customer_order_behavior` AS cob
        ON fcb.customer_email = cob.customer_email
    GROUP BY fcb.product_family_key
),

customer_first_order_ts AS (
    SELECT
        customer_email,
        MIN(created_at_ts) AS first_order_ts
    FROM trusted_line_base
    GROUP BY customer_email
),

customer_first_order_families AS (
    SELECT DISTINCT
        j.customer_email,
        j.product_family_key
    FROM joined AS j
    INNER JOIN customer_first_order_ts AS cfot
        ON j.customer_email = cfot.customer_email
       AND j.created_at_ts = cfot.first_order_ts
),

family_first_purchase AS (
    SELECT
        product_family_key,
        COUNT(DISTINCT customer_email) AS customers_first_buying_this_family
    FROM customer_first_order_families
    GROUP BY product_family_key
)

SELECT
    fr.product_family_key,
    fr.product_family_name,
    fr.customers_who_bought_family,
    fcm.one_time_customers_who_bought_family,
    fcm.repeat_customers_who_bought_family,
    ROUND(
        SAFE_DIVIDE(
            fcm.repeat_customers_who_bought_family,
            fr.customers_who_bought_family
        ),
        4
    ) AS pct_repeat_customers,
    fr.orders_containing_family,
    fr.units_sold,
    fr.gross_family_revenue,
    fr.net_family_revenue_before_refunds,
    fcm.avg_customer_lifetime_revenue,
    fcm.avg_customer_lifetime_orders,
    COALESCE(ffp.customers_first_buying_this_family, 0) AS customers_first_buying_this_family,
    ROUND(
        SAFE_DIVIDE(
            COALESCE(ffp.customers_first_buying_this_family, 0),
            fr.customers_who_bought_family
        ),
        4
    ) AS pct_of_family_customers_first_buying_this_family
FROM family_rollup AS fr
LEFT JOIN family_customer_metrics AS fcm
    ON fr.product_family_key = fcm.product_family_key
LEFT JOIN family_first_purchase AS ffp
    ON fr.product_family_key = ffp.product_family_key;
