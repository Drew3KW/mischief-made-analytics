-- File: sql/raw/create_shopify_products_api_raw_candidate.sql
-- Model: raw_load.shopify_products_api_raw_candidate
-- Purpose:
-- Create a CSV-compatible shadow raw products candidate from isolated
-- Shopify API product and variant landing tables.
--
-- Important notes:
-- - This does not modify raw.shopify_products.
-- - This does not modify staging, marts, or business-facing analysis.
-- - This table is for contract testing before any future canonical raw rebuild.
-- - Some CSV export fields are not available in the current API landing data
--   and are intentionally populated as NULL.

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.shopify_products_api_raw_candidate` AS

WITH products AS (
  SELECT
    shopify_product_graphql_id,
    legacy_resource_id,
    title,
    handle,
    vendor,
    product_type,
    status,
    tags_json
  FROM `mischief-made-analytics.raw_load.shopify_products_api_latest`
),

variants AS (
  SELECT
    shopify_product_variant_graphql_id,
    shopify_product_graphql_id,
    legacy_resource_id,
    title AS variant_title,
    sku,
    barcode,
    price,
    compare_at_price,
    taxable,
    inventory_quantity,
    selected_options_json
  FROM `mischief-made-analytics.raw_load.shopify_product_variants_api_latest`
)

SELECT
  products.handle,
  products.title,
  CAST(NULL AS STRING) AS body_html,
  products.vendor,
  CAST(NULL AS STRING) AS product_category,
  products.product_type AS type,
  COALESCE(ARRAY_TO_STRING(JSON_VALUE_ARRAY(products.tags_json, '$'), ', '), '') AS tags,
  CASE
    WHEN LOWER(products.status) = 'active' THEN 'TRUE'
    WHEN products.status IS NULL THEN NULL
    ELSE 'FALSE'
  END AS published,

  JSON_VALUE(variants.selected_options_json, '$[0].name') AS option1_name,
  JSON_VALUE(variants.selected_options_json, '$[0].value') AS option1_value,
  CAST(NULL AS STRING) AS option1_linked_to,
  JSON_VALUE(variants.selected_options_json, '$[1].name') AS option2_name,
  JSON_VALUE(variants.selected_options_json, '$[1].value') AS option2_value,
  CAST(NULL AS STRING) AS option2_linked_to,
  JSON_VALUE(variants.selected_options_json, '$[2].name') AS option3_name,
  JSON_VALUE(variants.selected_options_json, '$[2].value') AS option3_value,
  CAST(NULL AS STRING) AS option3_linked_to,

  variants.sku AS variant_sku,
  CAST(NULL AS STRING) AS variant_grams,
  CAST(NULL AS STRING) AS variant_inventory_tracker,
  CAST(variants.inventory_quantity AS STRING) AS variant_inventory_qty,
  CAST(NULL AS STRING) AS variant_inventory_policy,
  CAST(NULL AS STRING) AS variant_fulfillment_service,
  variants.price AS variant_price,
  variants.compare_at_price AS variant_compare_at_price,
  CAST(NULL AS STRING) AS variant_requires_shipping,
  CAST(variants.taxable AS STRING) AS variant_taxable,

  CAST(NULL AS STRING) AS unit_price_total_measure,
  CAST(NULL AS STRING) AS unit_price_total_measure_unit,
  CAST(NULL AS STRING) AS unit_price_base_measure,
  CAST(NULL AS STRING) AS unit_price_base_measure_unit,

  variants.barcode AS variant_barcode,
  CAST(NULL AS STRING) AS image_src,
  CAST(NULL AS STRING) AS image_position,
  CAST(NULL AS STRING) AS image_alt_text,
  CAST(NULL AS STRING) AS gift_card,
  CAST(NULL AS STRING) AS seo_title,
  CAST(NULL AS STRING) AS seo_description,

  CAST(NULL AS STRING) AS product_rating_count,
  CAST(NULL AS STRING) AS activewear_clothing_features,
  CAST(NULL AS STRING) AS activity,
  CAST(NULL AS STRING) AS age_group,
  CAST(NULL AS STRING) AS closure_type,
  CAST(NULL AS STRING) AS color,
  CAST(NULL AS STRING) AS decoration_material,
  CAST(NULL AS STRING) AS fabric,
  CAST(NULL AS STRING) AS footwear_material,
  CAST(NULL AS STRING) AS heel_height_type,
  CAST(NULL AS STRING) AS occasion_style,
  CAST(NULL AS STRING) AS pants_length_type,
  CAST(NULL AS STRING) AS sandal_style,
  CAST(NULL AS STRING) AS shoe_features,
  CAST(NULL AS STRING) AS shoe_size,
  CAST(NULL AS STRING) AS size,
  CAST(NULL AS STRING) AS target_gender,
  CAST(NULL AS STRING) AS toe_style,
  CAST(NULL AS STRING) AS waist_rise,

  CAST(NULL AS STRING) AS variant_image,
  CAST(NULL AS STRING) AS variant_weight_unit,
  CAST(NULL AS STRING) AS variant_tax_code,
  CAST(NULL AS STRING) AS cost_per_item,
  LOWER(products.status) AS status

FROM variants
LEFT JOIN products
  ON variants.shopify_product_graphql_id = products.shopify_product_graphql_id;