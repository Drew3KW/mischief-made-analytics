-- Model: marts.dim_products
-- Grain: one row per SKU
-- Purpose: current catalog product dimension built from Shopify product export
-- Notes:
--   - Represents current catalog state, not full historical sold-product coverage
--   - Deduplication prefers active status and more complete product attributes
--   - Fills null titles from the smallest titled sibling variant within a SKU family
--   - Cleans malformed leading size prefixes in titles
--   - Uses handle as a last-resort fallback for title completeness

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.dim_products` AS

WITH ranked_products AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY sku
      ORDER BY
        CASE WHEN LOWER(COALESCE(status, '')) = 'active' THEN 1 ELSE 2 END,
        CASE WHEN NULLIF(TRIM(title), '') IS NOT NULL THEN 1 ELSE 2 END,
        CASE WHEN price IS NOT NULL THEN 1 ELSE 2 END,
        CASE WHEN cost_per_item IS NOT NULL THEN 1 ELSE 2 END,
        CASE WHEN image_position IS NOT NULL THEN 1 ELSE 2 END,
        image_position,
        handle
    ) AS row_num
  FROM `mischief-made-analytics.staging.stg_shopify_products`
),

deduped_products AS (
  SELECT
    *
  FROM ranked_products
  WHERE row_num = 1
),

products_with_family_key AS (
  SELECT
    *,
    REGEXP_REPLACE(LOWER(TRIM(sku)), r'-(xs|s|m|l|xl|2xl|3xl|4xl|5xl)$', '') AS sku_family_key
  FROM deduped_products
),

titles_filled AS (
  SELECT
    sku,
    handle,
    COALESCE(
      clean_title,
      FIRST_VALUE(clean_title IGNORE NULLS) OVER (
        PARTITION BY sku_family_key
        ORDER BY size_rank
      )
    ) AS title,
    body_html,
    vendor,
    product_category,
    type,
    tags,
    published,
    option1_name,
    option1_value,
    option2_name,
    option2_value,
    option3_name,
    option3_value,
    price,
    compare_at_price,
    inventory_quantity,
    weight_grams,
    variant_inventory_tracker,
    variant_inventory_policy,
    variant_fulfillment_service,
    variant_requires_shipping,
    variant_taxable,
    image_src,
    image_position,
    image_alt_text,
    variant_barcode,
    variant_image,
    variant_weight_unit,
    cost_per_item,
    status
  FROM (
    SELECT
      *,
      REGEXP_REPLACE(
        NULLIF(TRIM(title), ''),
        r'(?i)^size\s+[a-z0-9]+\s*-\s*',
        ''
      ) AS clean_title,
      CASE
        WHEN REGEXP_CONTAINS(LOWER(TRIM(sku)), r'-xs$') THEN 1
        WHEN REGEXP_CONTAINS(LOWER(TRIM(sku)), r'-s$') THEN 2
        WHEN REGEXP_CONTAINS(LOWER(TRIM(sku)), r'-m$') THEN 3
        WHEN REGEXP_CONTAINS(LOWER(TRIM(sku)), r'-l$') THEN 4
        WHEN REGEXP_CONTAINS(LOWER(TRIM(sku)), r'-xl$') THEN 5
        WHEN REGEXP_CONTAINS(LOWER(TRIM(sku)), r'-2xl$') THEN 6
        WHEN REGEXP_CONTAINS(LOWER(TRIM(sku)), r'-3xl$') THEN 7
        WHEN REGEXP_CONTAINS(LOWER(TRIM(sku)), r'-4xl$') THEN 8
        WHEN REGEXP_CONTAINS(LOWER(TRIM(sku)), r'-5xl$') THEN 9
        ELSE 99
      END AS size_rank
    FROM products_with_family_key
  )
)

SELECT
  sku,
  handle,
  title,
  body_html,
  vendor,
  product_category,
  type,
  tags,
  published,
  option1_name,
  option1_value,
  option2_name,
  option2_value,
  option3_name,
  option3_value,
  price,
  compare_at_price,
  inventory_quantity,
  weight_grams,
  variant_inventory_tracker,
  variant_inventory_policy,
  variant_fulfillment_service,
  variant_requires_shipping,
  variant_taxable,
  image_src,
  image_position,
  image_alt_text,
  variant_barcode,
  variant_image,
  variant_weight_unit,
  cost_per_item,
  status
FROM titles_filled;
