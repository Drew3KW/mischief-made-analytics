-- sql/analysis/product_performance_by_family.sql
-- Purpose:
-- Business-facing product performance at product family grain.
--
-- Grain:
-- One row per product_family_key.
--
-- Revenue definition:
-- gross merchandise revenue = quantity * lineitem_price
--
-- Notes:
-- - Uses shared family models from marts.product_family_map and marts.dim_product_families
-- - Excludes cancelled orders
-- - Uses marts only

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_product_performance_by_family` AS

WITH line_base AS (
    SELECT
        oi.order_item_key,
        oi.order_number,
        oi.product_key,
        oi.quantity,
        oi.gross_item_revenue,
        DATE(o.created_at_ts) AS order_date
    FROM `mischief-made-analytics.marts.fct_order_items` AS oi
    INNER JOIN `mischief-made-analytics.marts.fct_orders` AS o
        ON oi.order_number = o.order_number
    WHERE o.cancelled_at_ts IS NULL
),

joined AS (
    SELECT
        lb.order_item_key,
        lb.order_number,
        pfm.product_family_key,
        dpf.product_family_name,
        lb.quantity,
        lb.gross_item_revenue,
        lb.order_date
    FROM line_base AS lb
    LEFT JOIN `mischief-made-analytics.marts.product_family_map` AS pfm
        ON lb.product_key = pfm.product_key
    LEFT JOIN `mischief-made-analytics.marts.dim_product_families` AS dpf
        ON pfm.product_family_key = dpf.product_family_key
    WHERE pfm.product_family_key IS NOT NULL
)

SELECT
    product_family_key,
    product_family_name,
    COUNT(DISTINCT order_number) AS orders_containing_family,
    SUM(quantity) AS units_sold,
    ROUND(SUM(gross_item_revenue), 2) AS gross_family_revenue,
    ROUND(AVG(gross_item_revenue), 2) AS avg_revenue_per_order_line,
    MIN(order_date) AS first_order_date,
    MAX(order_date) AS last_order_date
FROM joined
GROUP BY
    product_family_key,
    product_family_name;
