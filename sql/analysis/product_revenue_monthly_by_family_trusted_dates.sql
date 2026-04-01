-- sql/analysis/product_revenue_monthly_by_family_trusted_dates.sql
-- Purpose:
-- Monthly product family revenue trends using only trusted order dates.
--
-- Grain:
-- One row per order_month per product_family_key.
--
-- Revenue definition:
-- gross merchandise revenue = quantity * lineitem_price
--
-- Notes:
-- - Uses shared family models from marts.product_family_map and marts.dim_product_families
-- - Excludes cancelled orders
-- - Excludes orders flagged as suspect for historical timing anomalies
-- - Uses marts only

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_product_revenue_monthly_by_family_trusted_dates` AS

WITH line_base AS (
    SELECT
        DATE_TRUNC(DATE(o.created_at_ts), MONTH) AS order_month,
        oi.order_number,
        oi.product_key,
        oi.quantity,
        oi.gross_item_revenue
    FROM `mischief-made-analytics.marts.fct_order_items` AS oi
    INNER JOIN `mischief-made-analytics.marts.fct_orders` AS o
        ON oi.order_number = o.order_number
    WHERE o.cancelled_at_ts IS NULL
      AND o.is_suspect_historical_timing = FALSE
),

joined AS (
    SELECT
        lb.order_month,
        lb.order_number,
        pfm.product_family_key,
        dpf.product_family_name,
        lb.quantity,
        lb.gross_item_revenue
    FROM line_base AS lb
    LEFT JOIN `mischief-made-analytics.marts.product_family_map` AS pfm
        ON lb.product_key = pfm.product_key
    LEFT JOIN `mischief-made-analytics.marts.dim_product_families` AS dpf
        ON pfm.product_family_key = dpf.product_family_key
    WHERE pfm.product_family_key IS NOT NULL
)

SELECT
    order_month,
    product_family_key,
    product_family_name,
    COUNT(DISTINCT order_number) AS orders_containing_family,
    SUM(quantity) AS units_sold,
    ROUND(SUM(gross_item_revenue), 2) AS gross_family_revenue,
    ROUND(AVG(gross_item_revenue), 2) AS avg_revenue_per_order_line
FROM joined
GROUP BY
    order_month,
    product_family_key,
    product_family_name;
