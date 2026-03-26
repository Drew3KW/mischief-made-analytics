-- sql/analysis/product_family_recent_trends_review.sql
-- Purpose:
-- Business-facing review queries for recent product family trends.
--
-- Notes:
-- - Uses cleaned canonical family names from marts.anl_product_performance_by_family
-- - Keeps trend math from marts.anl_product_family_recent_trends_trusted
-- - Excludes obvious non-core items like mystery boxes / bundles / promos
-- - Adds variant drill-down for selected candidate families

--------------------------------------------------------------------------------
-- 1) Top risers (core apparel only)
--------------------------------------------------------------------------------

WITH cleaned_family_trends AS (
  SELECT
    t.product_family_key,
    p.product_family_name,
    p.units_sold,
    p.gross_family_revenue,
    t.lifetime_months_with_sales,
    t.first_trusted_month_sold,
    t.most_recent_trusted_month_sold,
    t.revenue_last_3m,
    t.revenue_prior_3m,
    t.revenue_change_3m_vs_prior_3m,
    t.revenue_pct_change_3m_vs_prior_3m,
    t.units_last_3m,
    t.units_prior_3m,
    t.units_change_3m_vs_prior_3m,
    t.units_pct_change_3m_vs_prior_3m,
    t.months_with_sales_last_3m,
    t.months_with_sales_prior_3m,
    t.trend_status
  FROM `mischief-made-analytics.marts.anl_product_family_recent_trends_trusted` AS t
  INNER JOIN `mischief-made-analytics.marts.anl_product_performance_by_family` AS p
    ON t.product_family_key = p.product_family_key
  WHERE NOT REGEXP_CONTAINS(
    LOWER(COALESCE(t.product_family_key, '')),
    r'(mystery|bundle|box|gift[\-_ ]?card|giftcard|mto|made[\-_ ]?to[\-_ ]?order|promo|sample|test)'
  )
    AND NOT REGEXP_CONTAINS(
      LOWER(COALESCE(p.product_family_name, '')),
      r'(mystery|bundle|box|gift[\-_ ]?card|giftcard|promo|sample|test)'
    )
)

SELECT
  product_family_key,
  product_family_name,
  lifetime_months_with_sales,
  first_trusted_month_sold,
  most_recent_trusted_month_sold,
  revenue_last_3m,
  revenue_prior_3m,
  revenue_change_3m_vs_prior_3m,
  revenue_pct_change_3m_vs_prior_3m,
  units_last_3m,
  units_prior_3m,
  units_change_3m_vs_prior_3m,
  units_pct_change_3m_vs_prior_3m,
  months_with_sales_last_3m,
  months_with_sales_prior_3m,
  trend_status
FROM cleaned_family_trends
WHERE trend_status = 'rising'
  AND revenue_last_3m >= 100
ORDER BY revenue_change_3m_vs_prior_3m DESC, units_change_3m_vs_prior_3m DESC
LIMIT 25;

--------------------------------------------------------------------------------
-- 2) Top decliners (core apparel only)
--------------------------------------------------------------------------------

WITH cleaned_family_trends AS (
  SELECT
    t.product_family_key,
    p.product_family_name,
    p.units_sold,
    p.gross_family_revenue,
    t.lifetime_months_with_sales,
    t.first_trusted_month_sold,
    t.most_recent_trusted_month_sold,
    t.revenue_last_3m,
    t.revenue_prior_3m,
    t.revenue_change_3m_vs_prior_3m,
    t.revenue_pct_change_3m_vs_prior_3m,
    t.units_last_3m,
    t.units_prior_3m,
    t.units_change_3m_vs_prior_3m,
    t.units_pct_change_3m_vs_prior_3m,
    t.months_with_sales_last_3m,
    t.months_with_sales_prior_3m,
    t.trend_status
  FROM `mischief-made-analytics.marts.anl_product_family_recent_trends_trusted` AS t
  INNER JOIN `mischief-made-analytics.marts.anl_product_performance_by_family` AS p
    ON t.product_family_key = p.product_family_key
  WHERE NOT REGEXP_CONTAINS(
    LOWER(COALESCE(t.product_family_key, '')),
    r'(mystery|bundle|box|gift[\-_ ]?card|giftcard|mto|made[\-_ ]?to[\-_ ]?order|promo|sample|test)'
  )
    AND NOT REGEXP_CONTAINS(
      LOWER(COALESCE(p.product_family_name, '')),
      r'(mystery|bundle|box|gift[\-_ ]?card|giftcard|promo|sample|test)'
    )
)

SELECT
  product_family_key,
  product_family_name,
  lifetime_months_with_sales,
  first_trusted_month_sold,
  most_recent_trusted_month_sold,
  revenue_last_3m,
  revenue_prior_3m,
  revenue_change_3m_vs_prior_3m,
  revenue_pct_change_3m_vs_prior_3m,
  units_last_3m,
  units_prior_3m,
  units_change_3m_vs_prior_3m,
  units_pct_change_3m_vs_prior_3m,
  months_with_sales_last_3m,
  months_with_sales_prior_3m,
  trend_status
FROM cleaned_family_trends
WHERE trend_status = 'declining'
  AND revenue_prior_3m >= 100
ORDER BY revenue_change_3m_vs_prior_3m ASC, units_change_3m_vs_prior_3m ASC
LIMIT 25;

--------------------------------------------------------------------------------
-- 3) New or returning families (core apparel only)
--------------------------------------------------------------------------------

WITH cleaned_family_trends AS (
  SELECT
    t.product_family_key,
    p.product_family_name,
    p.units_sold,
    p.gross_family_revenue,
    t.lifetime_months_with_sales,
    t.first_trusted_month_sold,
    t.most_recent_trusted_month_sold,
    t.revenue_last_3m,
    t.revenue_prior_3m,
    t.revenue_change_3m_vs_prior_3m,
    t.revenue_pct_change_3m_vs_prior_3m,
    t.units_last_3m,
    t.units_prior_3m,
    t.units_change_3m_vs_prior_3m,
    t.units_pct_change_3m_vs_prior_3m,
    t.months_with_sales_last_3m,
    t.months_with_sales_prior_3m,
    t.trend_status
  FROM `mischief-made-analytics.marts.anl_product_family_recent_trends_trusted` AS t
  INNER JOIN `mischief-made-analytics.marts.anl_product_performance_by_family` AS p
    ON t.product_family_key = p.product_family_key
  WHERE NOT REGEXP_CONTAINS(
    LOWER(COALESCE(t.product_family_key, '')),
    r'(mystery|bundle|box|gift[\-_ ]?card|giftcard|mto|made[\-_ ]?to[\-_ ]?order|promo|sample|test)'
  )
    AND NOT REGEXP_CONTAINS(
      LOWER(COALESCE(p.product_family_name, '')),
      r'(mystery|bundle|box|gift[\-_ ]?card|giftcard|promo|sample|test)'
    )
)

SELECT
  product_family_key,
  product_family_name,
  lifetime_months_with_sales,
  first_trusted_month_sold,
  most_recent_trusted_month_sold,
  revenue_last_3m,
  revenue_prior_3m,
  units_last_3m,
  units_prior_3m,
  months_with_sales_last_3m,
  months_with_sales_prior_3m,
  trend_status
FROM cleaned_family_trends
WHERE trend_status = 'new_or_returning'
ORDER BY revenue_last_3m DESC, units_last_3m DESC
LIMIT 25;

--------------------------------------------------------------------------------
-- 4) Top lifetime performers still rising
--------------------------------------------------------------------------------

WITH cleaned_family_trends AS (
  SELECT
    t.product_family_key,
    p.product_family_name,
    p.units_sold,
    p.gross_family_revenue,
    t.lifetime_months_with_sales,
    t.first_trusted_month_sold,
    t.most_recent_trusted_month_sold,
    t.revenue_last_3m,
    t.revenue_prior_3m,
    t.revenue_change_3m_vs_prior_3m,
    t.revenue_pct_change_3m_vs_prior_3m,
    t.units_last_3m,
    t.units_prior_3m,
    t.units_change_3m_vs_prior_3m,
    t.units_pct_change_3m_vs_prior_3m,
    t.months_with_sales_last_3m,
    t.months_with_sales_prior_3m,
    t.trend_status
  FROM `mischief-made-analytics.marts.anl_product_family_recent_trends_trusted` AS t
  INNER JOIN `mischief-made-analytics.marts.anl_product_performance_by_family` AS p
    ON t.product_family_key = p.product_family_key
  WHERE NOT REGEXP_CONTAINS(
    LOWER(COALESCE(t.product_family_key, '')),
    r'(mystery|bundle|box|gift[\-_ ]?card|giftcard|mto|made[\-_ ]?to[\-_ ]?order|promo|sample|test)'
  )
    AND NOT REGEXP_CONTAINS(
      LOWER(COALESCE(p.product_family_name, '')),
      r'(mystery|bundle|box|gift[\-_ ]?card|giftcard|promo|sample|test)'
    )
)

SELECT
  product_family_key,
  product_family_name,
  units_sold,
  lifetime_months_with_sales,
  units_last_3m,
  units_prior_3m,
  units_change_3m_vs_prior_3m,
  units_pct_change_3m_vs_prior_3m,
  trend_status,
  gross_family_revenue
FROM cleaned_family_trends
WHERE trend_status = 'rising'
  AND lifetime_months_with_sales >= 24
ORDER BY lifetime_months_with_sales DESC, gross_family_revenue DESC
LIMIT 25;

--------------------------------------------------------------------------------
-- 5) Variant drill-down for selected high-priority candidate families
--------------------------------------------------------------------------------

WITH max_month AS (
  SELECT
    MAX(order_month) AS latest_month
  FROM `mischief-made-analytics.marts.anl_product_revenue_monthly_by_family_trusted_dates`
),

candidate_families AS (
  SELECT 'ts-dag-ra' AS product_family_key UNION ALL
  SELECT 'ca-hol-pi' UNION ALL
  SELECT 'ts-val-iv' UNION ALL
  SELECT 'ca-eye-bk'
),

product_base AS (
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

family_lookup AS (
  SELECT
    product_key,
    CASE
      WHEN normalized_sku IS NOT NULL
       AND normalized_sku != ''
       AND normalized_sku NOT IN (
         'sticker','stickers','greeting card','greeting-card','greeting_card',
         'card','cards','patch','patches','pin','pins','magnet','magnets',
         'tote bag','tote-bag','tote_bag','tote','decal','decal sticker'
       )
       AND normalized_sku_family NOT IN (
         'sticker','stickers','greeting card','greeting-card','greeting_card',
         'card','cards','patch','patches','pin','pins','magnet','magnets',
         'tote bag','tote-bag','tote_bag','tote','decal','decal sticker'
       )
      THEN normalized_sku_family

      WHEN normalized_product_name IS NULL
        OR normalized_product_name = ''
        OR normalized_product_name IN (
          'sticker','stickers','greeting card','card','cards','patch','patches',
          'pin','pins','magnet','magnets','tote bag','tote','decal','decal sticker'
        )
      THEN normalized_product_key

      ELSE normalized_product_name_family_key
    END AS product_family_key
  FROM product_base
),

family_names AS (
  SELECT
    product_family_key,
    ANY_VALUE(product_family_name) AS product_family_name
  FROM `mischief-made-analytics.marts.anl_product_performance_by_family`
  GROUP BY product_family_key
),

variant_base AS (
  SELECT
    fl.product_family_key,
    COALESCE(NULLIF(TRIM(oi.sku), ''), '[no sku]') AS sku,
    COALESCE(NULLIF(TRIM(oi.product_name), ''), '[no product name]') AS product_name,
    DATE_TRUNC(DATE(o.created_at_ts), MONTH) AS order_month,
    oi.quantity,
    oi.lineitem_price,
    oi.quantity * oi.lineitem_price AS gross_item_revenue
  FROM `mischief-made-analytics.marts.fct_order_items` AS oi
  INNER JOIN `mischief-made-analytics.marts.fct_orders` AS o
    ON oi.order_number = o.order_number
  INNER JOIN family_lookup AS fl
    ON oi.product_key = fl.product_key
  INNER JOIN candidate_families AS cf
    ON fl.product_family_key = cf.product_family_key
  WHERE o.cancelled_at_ts IS NULL
),

variant_rollup AS (
  SELECT
    vb.product_family_key,
    vb.sku,
    vb.product_name,

    SUM(CASE
      WHEN vb.order_month BETWEEN DATE_SUB(mm.latest_month, INTERVAL 2 MONTH) AND mm.latest_month
      THEN vb.quantity
      ELSE 0
    END) AS units_last_3m,

    ROUND(SUM(CASE
      WHEN vb.order_month BETWEEN DATE_SUB(mm.latest_month, INTERVAL 2 MONTH) AND mm.latest_month
      THEN vb.gross_item_revenue
      ELSE 0
    END), 2) AS revenue_last_3m,

    SUM(CASE
      WHEN vb.order_month BETWEEN DATE_SUB(mm.latest_month, INTERVAL 5 MONTH) AND DATE_SUB(mm.latest_month, INTERVAL 3 MONTH)
      THEN vb.quantity
      ELSE 0
    END) AS units_prior_3m,

    ROUND(SUM(CASE
      WHEN vb.order_month BETWEEN DATE_SUB(mm.latest_month, INTERVAL 5 MONTH) AND DATE_SUB(mm.latest_month, INTERVAL 3 MONTH)
      THEN vb.gross_item_revenue
      ELSE 0
    END), 2) AS revenue_prior_3m,

    SUM(vb.quantity) AS lifetime_units_sold,
    ROUND(SUM(vb.gross_item_revenue), 2) AS lifetime_revenue
  FROM variant_base AS vb
  CROSS JOIN max_month AS mm
  GROUP BY
    vb.product_family_key,
    vb.sku,
    vb.product_name
)

SELECT
  vr.product_family_key,
  fn.product_family_name,
  vr.sku,
  vr.product_name,
  vr.lifetime_units_sold,
  vr.lifetime_revenue,
  vr.units_last_3m,
  vr.units_prior_3m,
  vr.units_last_3m - vr.units_prior_3m AS units_change_3m_vs_prior_3m,
  CASE
    WHEN vr.units_prior_3m = 0 AND vr.units_last_3m > 0 THEN NULL
    ELSE ROUND(((vr.units_last_3m - vr.units_prior_3m) / NULLIF(vr.units_prior_3m, 0)) * 100, 2)
  END AS units_pct_change_3m_vs_prior_3m,
  vr.revenue_last_3m,
  vr.revenue_prior_3m,
  ROUND(vr.revenue_last_3m - vr.revenue_prior_3m, 2) AS revenue_change_3m_vs_prior_3m,
  CASE
    WHEN vr.revenue_prior_3m = 0 AND vr.revenue_last_3m > 0 THEN NULL
    ELSE ROUND(((vr.revenue_last_3m - vr.revenue_prior_3m) / NULLIF(vr.revenue_prior_3m, 0)) * 100, 2)
  END AS revenue_pct_change_3m_vs_prior_3m
FROM variant_rollup AS vr
LEFT JOIN family_names AS fn
  ON vr.product_family_key = fn.product_family_key
WHERE vr.lifetime_units_sold > 0
ORDER BY
  vr.product_family_key,
  vr.units_last_3m DESC,
  vr.revenue_last_3m DESC,
  vr.lifetime_units_sold DESC,
  vr.sku;
