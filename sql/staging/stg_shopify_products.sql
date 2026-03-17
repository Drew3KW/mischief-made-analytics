-- Model: staging.stg_shopify_products
-- Grain: intended one row per product variant / SKU before downstream deduplication
-- Purpose: cleaned Shopify product export for catalog modeling
-- Notes:
--   - Blank SKUs are filtered out for downstream dimensional modeling
--   - Source profiling revealed true duplicate SKU issues in the catalog

CREATE OR REPLACE TABLE `mischief-made-analytics.staging.stg_shopify_products` AS

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

FROM `mischief-made-analytics.raw.shopify_products`
WHERE NULLIF(TRIM(variant_sku), '') IS NOT NULL;
