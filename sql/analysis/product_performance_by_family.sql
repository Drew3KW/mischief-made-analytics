-- sql/analysis/product_performance_by_family.sql
-- Purpose:
-- Business-facing product performance at product family grain.
-- Grain: one row per product_family_key.
--
-- Revenue definition:
-- gross merchandise revenue = quantity * lineitem_price
--
-- Notes:
-- - Uses marts only
-- - Rolls size variants up into product families
-- - Avoids over-grouping when sku or product_name is too generic
-- - Keeps color info as part of the product family name
-- - Strips lingering size/body-related suffixes from family names
-- - Excludes cancelled orders

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_product_performance_by_family` AS

WITH product_base AS (
  SELECT
    dph.product_key,
    dph.product_name,
    dph.sku,

    LOWER(TRIM(dph.product_key)) AS normalized_product_key,
    LOWER(TRIM(dph.sku)) AS normalized_sku,

    REGEXP_REPLACE(
      LOWER(TRIM(dph.sku)),
      r'-(xxs|xs|s|m|l|xl|xxl|2x|2xl|3x|3xl|4x|4xl|5x|5xl|6x|6xl|3xk)$',
      ''
    ) AS normalized_sku_family,

    LOWER(TRIM(dph.product_name)) AS normalized_product_name,

    REGEXP_REPLACE(
      LOWER(TRIM(dph.product_name)),
      r'[^a-z0-9]+',
      '_'
    ) AS normalized_product_name_key,

    REGEXP_REPLACE(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          LOWER(TRIM(dph.product_name)),
          r'[^a-z0-9]+',
          '_'
        ),
        r'_(xx_small|x_small|small|medium|large|x_large|xx_large|xxx_large|xl|xxl|xxxl|1x|2x|3x|4x|5x|6x|1x_large|2x_large|3x_large|4x_large|5x_large|6x_large|2xl|3xl|4xl|5xl|6xl)$',
        ''
      ),
      r'_(design|art)_by_[a-z0-9_]+$',
      ''
    ) AS normalized_product_name_family_key
  FROM `mischief-made-analytics.marts.dim_products_historical` AS dph
),

family_logic AS (
  SELECT
    product_key,
    product_name,
    sku,

    CASE
      WHEN normalized_sku IS NOT NULL
       AND normalized_sku != ''
       AND normalized_sku NOT IN (
         'sticker',
         'stickers',
         'greeting card',
         'greeting-card',
         'greeting_card',
         'card',
         'cards',
         'patch',
         'patches',
         'pin',
         'pins',
         'magnet',
         'magnets',
         'tote bag',
         'tote-bag',
         'tote_bag',
         'tote',
         'decal',
         'decal sticker'
       )
       AND normalized_sku_family NOT IN (
         'sticker',
         'stickers',
         'greeting card',
         'greeting-card',
         'greeting_card',
         'card',
         'cards',
         'patch',
         'patches',
         'pin',
         'pins',
         'magnet',
         'magnets',
         'tote bag',
         'tote-bag',
         'tote_bag',
         'tote',
         'decal',
         'decal sticker'
       )
      THEN normalized_sku_family

      WHEN normalized_product_name IS NULL
        OR normalized_product_name = ''
        OR normalized_product_name IN (
          'sticker',
          'stickers',
          'greeting card',
          'card',
          'cards',
          'patch',
          'patches',
          'pin',
          'pins',
          'magnet',
          'magnets',
          'tote bag',
          'tote',
          'decal',
          'decal sticker'
        )
      THEN normalized_product_key

      ELSE normalized_product_name_family_key
    END AS product_family_key,

    CASE
      WHEN product_name IS NOT NULL AND TRIM(product_name) != '' THEN product_name
      WHEN sku IS NOT NULL AND TRIM(sku) != '' THEN sku
      ELSE product_key
    END AS raw_product_family_name
  FROM product_base
),

cleaned_family_names AS (
  SELECT
    product_key,
    product_family_key,
    raw_product_family_name,

    TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            REGEXP_REPLACE(
              REGEXP_REPLACE(
                raw_product_family_name,
                r"^\[[^\]]+\]\s*",
                ''
              ),
              r"(?i)\s*-\s*(unisex|ladies|womens|mens)?\s*-?\s*(xxs|xs|s|m|l|xl|xxl|xxxl|1x|2x|3x|4x|5x|6x|2xl|3xl|4xl|5xl|6xl|x-large|xx-large|xxx-large|2x-large|3x-large|4x-large|5x-large|6x-large)\s*$",
              ''
            ),
            r"(?i)\s+(unisex|ladies|womens|mens)\s+body\s*$",
            ''
          ),
          r"(?i)\s+(unisex|ladies|womens|mens)\s*$",
          ''
        ),
        r"\s+",
        ' '
      )
    ) AS cleaned_product_family_name
  FROM family_logic
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
    cfn.product_family_key,
    cfn.cleaned_product_family_name AS product_family_name,
    lb.quantity,
    lb.gross_item_revenue,
    lb.order_date
  FROM line_base AS lb
  LEFT JOIN cleaned_family_names AS cfn
    ON lb.product_key = cfn.product_key
  WHERE cfn.product_family_key IS NOT NULL
),

family_metrics AS (
  SELECT
    product_family_key,
    COUNT(DISTINCT order_number) AS orders_containing_family,
    SUM(quantity) AS units_sold,
    ROUND(SUM(gross_item_revenue), 2) AS gross_family_revenue,
    ROUND(AVG(gross_item_revenue), 2) AS avg_revenue_per_order_line,
    MIN(order_date) AS first_order_date,
    MAX(order_date) AS last_order_date
  FROM joined
  GROUP BY product_family_key
),

canonical_family_names AS (
  SELECT
    product_family_key,
    product_family_name
  FROM (
    SELECT
      product_family_key,
      product_family_name,
      COUNT(*) AS line_count,
      SUM(quantity) AS total_units,
      ROUND(SUM(gross_item_revenue), 2) AS total_revenue,
      ROW_NUMBER() OVER (
        PARTITION BY product_family_key
        ORDER BY
          SUM(quantity) DESC,
          SUM(gross_item_revenue) DESC,
          COUNT(*) DESC,
          LENGTH(product_family_name) ASC,
          product_family_name ASC
      ) AS rn
    FROM joined
    WHERE product_family_name IS NOT NULL
      AND TRIM(product_family_name) != ''
    GROUP BY
      product_family_key,
      product_family_name
  )
  WHERE rn = 1
)

SELECT
  fm.product_family_key,
  cfn.product_family_name,
  fm.orders_containing_family,
  fm.units_sold,
  fm.gross_family_revenue,
  fm.avg_revenue_per_order_line,
  fm.first_order_date,
  fm.last_order_date
FROM family_metrics AS fm
LEFT JOIN canonical_family_names AS cfn
  ON fm.product_family_key = cfn.product_family_key;
