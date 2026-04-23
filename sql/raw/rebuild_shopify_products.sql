-- File: sql/raw/rebuild_shopify_products.sql
-- Model: raw.shopify_products
-- Purpose:
--   Rebuild the canonical raw Shopify products table by combining:
--   1) existing canonical raw history
--   2) the latest landed import table
--   then deduplicating to preserve one preferred row per product-variant key.
--
-- Grain:
--   Intended one row per Shopify product variant / SKU in the raw export.
--
-- Important notes:
-- - We explicitly align incoming landing columns to the historical canonical
--   raw column contract rather than relying on SELECT *.
-- - This is necessary because newer Shopify product exports renamed several
--   metafield columns and added extra market/pricing columns that do not
--   exist in the historical canonical raw table.
-- - For MVP, we preserve the existing canonical raw schema and ignore the
--   extra market/pricing columns in the landing table.
-- - When the same dedupe key appears in both existing and incoming data,
--   the incoming row wins.

CREATE OR REPLACE TABLE `mischief-made-analytics.raw.shopify_products` AS
WITH combined AS (
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
    option1_linked_to,
    option2_name,
    option2_value,
    option2_linked_to,
    option3_name,
    option3_value,
    option3_linked_to,
    variant_sku,
    variant_grams,
    variant_inventory_tracker,
    variant_inventory_qty,
    variant_inventory_policy,
    variant_fulfillment_service,
    variant_price,
    variant_compare_at_price,
    variant_requires_shipping,
    variant_taxable,
    unit_price_total_measure,
    unit_price_total_measure_unit,
    unit_price_base_measure,
    unit_price_base_measure_unit,
    variant_barcode,
    image_src,
    image_position,
    image_alt_text,
    gift_card,
    seo_title,
    seo_description,
    product_rating_count,
    activewear_clothing_features,
    activity,
    age_group,
    closure_type,
    color,
    decoration_material,
    fabric,
    footwear_material,
    heel_height_type,
    occasion_style,
    pants_length_type,
    sandal_style,
    shoe_features,
    shoe_size,
    size,
    target_gender,
    toe_style,
    waist_rise,
    variant_image,
    variant_weight_unit,
    variant_tax_code,
    cost_per_item,
    status,
    0 AS source_rank
  FROM `mischief-made-analytics.raw.shopify_products`

  UNION ALL

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
    option1_linked_to,
    option2_name,
    option2_value,
    option2_linked_to,
    option3_name,
    option3_value,
    option3_linked_to,
    variant_sku,
    variant_grams,
    variant_inventory_tracker,
    variant_inventory_qty,
    variant_inventory_policy,
    variant_fulfillment_service,
    variant_price,
    variant_compare_at_price,
    variant_requires_shipping,
    variant_taxable,
    unit_price_total_measure,
    unit_price_total_measure_unit,
    unit_price_base_measure,
    unit_price_base_measure_unit,
    variant_barcode,
    image_src,
    image_position,
    image_alt_text,
    gift_card,
    seo_title,
    seo_description,
    product_rating_count_product_metafields_reviews_rating_count AS product_rating_count,
    activewear_clothing_features_product_metafields_shopify_activewear_clothing_features AS activewear_clothing_features,
    activity_product_metafields_shopify_activity AS activity,
    age_group_product_metafields_shopify_age_group AS age_group,
    closure_type_product_metafields_shopify_closure_type AS closure_type,
    color_product_metafields_shopify_color_pattern AS color,
    decoration_material_product_metafields_shopify_decoration_material AS decoration_material,
    fabric_product_metafields_shopify_fabric AS fabric,
    footwear_material_product_metafields_shopify_footwear_material AS footwear_material,
    heel_height_type_product_metafields_shopify_heel_height_type AS heel_height_type,
    occasion_style_product_metafields_shopify_occasion_style AS occasion_style,
    pants_length_type_product_metafields_shopify_pants_length_type AS pants_length_type,
    sandal_style_product_metafields_shopify_sandal_style AS sandal_style,
    shoe_features_product_metafields_shopify_shoe_features AS shoe_features,
    shoe_size_product_metafields_shopify_shoe_size AS shoe_size,
    size_product_metafields_shopify_size AS size,
    target_gender_product_metafields_shopify_target_gender AS target_gender,
    toe_style_product_metafields_shopify_toe_style AS toe_style,
    waist_rise_product_metafields_shopify_waist_rise AS waist_rise,
    variant_image,
    variant_weight_unit,
    variant_tax_code,
    cost_per_item,
    status,
    1 AS source_rank
  FROM `mischief-made-analytics.raw_load.shopify_products_latest`
),

keyed AS (
  SELECT
    * EXCEPT(source_rank),
    source_rank,
    CASE
      WHEN NULLIF(LOWER(TRIM(variant_sku)), '') IS NOT NULL THEN
        CONCAT('sku::', LOWER(TRIM(variant_sku)))
      WHEN NULLIF(LOWER(TRIM(handle)), '') IS NOT NULL THEN
        CONCAT(
          'handle_options::',
          LOWER(TRIM(handle)), '||',
          COALESCE(LOWER(TRIM(option1_value)), ''), '||',
          COALESCE(LOWER(TRIM(option2_value)), ''), '||',
          COALESCE(LOWER(TRIM(option3_value)), '')
        )
      ELSE
        CONCAT(
          'handle_title::',
          COALESCE(LOWER(TRIM(handle)), ''), '||',
          COALESCE(LOWER(TRIM(title)), '')
        )
    END AS dedupe_key
  FROM combined
),

deduped AS (
  SELECT
    * EXCEPT(source_rank, dedupe_key)
  FROM keyed
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY dedupe_key
    ORDER BY source_rank DESC
  ) = 1
)

SELECT *
FROM deduped;