-- sql/analysis/product_performance_by_family.sql
-- Purpose:
-- Business-facing product performance at product family grain.
-- Grain: one row per product_family_key.
--
-- Revenue definition:
-- gross merchandise revenue = quantity * line_item_price
--
-- Notes:
-- - Uses marts only
-- - Rolls size variants up into product families
-- - Falls back to product_name when sku is null
-- - Excludes cancelled orders

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_product_performance_by_family` AS

WITH product_base AS (
  SELECT
    dph.product_key,
    dph.product_name,
    dph.sku,

    CASE
      WHEN dph.sku IS NOT NULL THEN
        REGEXP_REPLACE(
          LOWER(TRIM(dph.sku)),
          r'-(xxs|xs|s|m|l|xl|xxl|2x|2xl|3x|3xl|4x|4xl|5x|5xl|6x|6xl|3xk)$',
          ''
        )
      ELSE
        REGEXP_REPLACE(
          LOWER(TRIM(dph.product_name)),
          r'[^a-z0-9]+',
          '_'
        )
    END AS product_family_key,

    CASE
      WHEN dph.product_name IS NOT NULL THEN dph.product_name
      WHEN dph.sku IS NOT NULL THEN dph.sku
      ELSE 'Unknown product family'
    END AS product_family_name
  FROM `mischief-made-analytics.marts.dim_products_historical` AS dph
),

line_base AS (
  SELECT
    oi.order_item_key,
    oi.order_number,
    oi.product_key,
    oi.quantity,
    oi.lineitem_price,
    oi.quantity * oi.lineitem_price AS gross_item_revenue,
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
    pb.product_family_key,
    pb.product_family_name,
    lb.quantity,
    lb.gross_item_revenue,
    lb.order_date
  FROM line_base AS lb
  LEFT JOIN product_base AS pb
    ON lb.product_key = pb.product_key
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
