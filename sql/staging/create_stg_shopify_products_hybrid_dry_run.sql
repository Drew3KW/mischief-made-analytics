-- File: sql/staging/create_stg_shopify_products_hybrid_dry_run.sql
-- Model: raw_load.stg_shopify_products_hybrid_dry_run
-- Purpose:
-- Simulate staging.stg_shopify_products using the Shopify hybrid raw product
-- candidate instead of production raw.shopify_products.
--
-- Important notes:
-- - This does not modify raw.shopify_products.
-- - This does not modify staging.stg_shopify_products.
-- - This dry-run table is isolated in raw_load.

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.stg_shopify_products_hybrid_dry_run` AS

SELECT
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
  TRIM(variant_sku) AS sku,
  SAFE_CAST(variant_price AS NUMERIC) AS price,
  SAFE_CAST(variant_compare_at_price AS NUMERIC) AS compare_at_price,
  SAFE_CAST(variant_inventory_qty AS INT64) AS inventory_quantity,
  SAFE_CAST(variant_grams AS INT64) AS weight_grams,
  variant_inventory_tracker,
  variant_inventory_policy,
  variant_fulfillment_service,
  variant_requires_shipping,
  variant_taxable,
  image_src,
  SAFE_CAST(image_position AS INT64) AS image_position,
  image_alt_text,
  variant_barcode,
  variant_image,
  variant_weight_unit,
  SAFE_CAST(cost_per_item AS NUMERIC) AS cost_per_item,
  status
FROM `mischief-made-analytics.raw_load.shopify_products_hybrid_raw_candidate`
WHERE NULLIF(TRIM(variant_sku), '') IS NOT NULL;