-- Model: marts.dim_products
-- Grain: one row per SKU
-- Purpose: current catalog product dimension built from Shopify product export
-- Notes:
--   - Represents current catalog state, not full historical sold-product coverage
--   - Deduplication prefers active status and more complete product attributes

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
FROM ranked_products
WHERE row_num = 1;
