-- File: sql/raw/create_shopify_products_hybrid_raw_candidate.sql
-- Model: raw_load.shopify_products_hybrid_raw_candidate
-- Purpose:
-- Create a non-production hybrid raw products candidate by combining:
-- 1) current CSV-derived canonical raw products
-- 2) API-derived raw product candidates
--
-- Important notes:
-- - This does not modify raw.shopify_products.
-- - This does not modify staging, marts, analysis, or DAG behavior.
-- - API-derived rows win when they share the same dedupe key as CSV-derived rows.
-- - This table is for validation before any future canonical raw replacement.

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.shopify_products_hybrid_raw_candidate` AS

WITH combined AS (
  SELECT
    CAST(handle AS STRING) AS handle,
    CAST(title AS STRING) AS title,
    CAST(body_html AS STRING) AS body_html,
    CAST(vendor AS STRING) AS vendor,
    CAST(product_category AS STRING) AS product_category,
    CAST(type AS STRING) AS type,
    CAST(tags AS STRING) AS tags,
    CAST(published AS STRING) AS published,
    CAST(option1_name AS STRING) AS option1_name,
    CAST(option1_value AS STRING) AS option1_value,
    CAST(option1_linked_to AS STRING) AS option1_linked_to,
    CAST(option2_name AS STRING) AS option2_name,
    CAST(option2_value AS STRING) AS option2_value,
    CAST(option2_linked_to AS STRING) AS option2_linked_to,
    CAST(option3_name AS STRING) AS option3_name,
    CAST(option3_value AS STRING) AS option3_value,
    CAST(option3_linked_to AS STRING) AS option3_linked_to,
    CAST(variant_sku AS STRING) AS variant_sku,
    CAST(variant_grams AS STRING) AS variant_grams,
    CAST(variant_inventory_tracker AS STRING) AS variant_inventory_tracker,
    CAST(variant_inventory_qty AS STRING) AS variant_inventory_qty,
    CAST(variant_inventory_policy AS STRING) AS variant_inventory_policy,
    CAST(variant_fulfillment_service AS STRING) AS variant_fulfillment_service,
    CAST(variant_price AS STRING) AS variant_price,
    CAST(variant_compare_at_price AS STRING) AS variant_compare_at_price,
    CAST(variant_requires_shipping AS STRING) AS variant_requires_shipping,
    CAST(variant_taxable AS STRING) AS variant_taxable,
    CAST(unit_price_total_measure AS STRING) AS unit_price_total_measure,
    CAST(unit_price_total_measure_unit AS STRING) AS unit_price_total_measure_unit,
    CAST(unit_price_base_measure AS STRING) AS unit_price_base_measure,
    CAST(unit_price_base_measure_unit AS STRING) AS unit_price_base_measure_unit,
    CAST(variant_barcode AS STRING) AS variant_barcode,
    CAST(image_src AS STRING) AS image_src,
    CAST(image_position AS STRING) AS image_position,
    CAST(image_alt_text AS STRING) AS image_alt_text,
    CAST(gift_card AS STRING) AS gift_card,
    CAST(seo_title AS STRING) AS seo_title,
    CAST(seo_description AS STRING) AS seo_description,
    CAST(product_rating_count AS STRING) AS product_rating_count,
    CAST(activewear_clothing_features AS STRING) AS activewear_clothing_features,
    CAST(activity AS STRING) AS activity,
    CAST(age_group AS STRING) AS age_group,
    CAST(closure_type AS STRING) AS closure_type,
    CAST(color AS STRING) AS color,
    CAST(decoration_material AS STRING) AS decoration_material,
    CAST(fabric AS STRING) AS fabric,
    CAST(footwear_material AS STRING) AS footwear_material,
    CAST(heel_height_type AS STRING) AS heel_height_type,
    CAST(occasion_style AS STRING) AS occasion_style,
    CAST(pants_length_type AS STRING) AS pants_length_type,
    CAST(sandal_style AS STRING) AS sandal_style,
    CAST(shoe_features AS STRING) AS shoe_features,
    CAST(shoe_size AS STRING) AS shoe_size,
    CAST(size AS STRING) AS size,
    CAST(target_gender AS STRING) AS target_gender,
    CAST(toe_style AS STRING) AS toe_style,
    CAST(waist_rise AS STRING) AS waist_rise,
    CAST(variant_image AS STRING) AS variant_image,
    CAST(variant_weight_unit AS STRING) AS variant_weight_unit,
    CAST(variant_tax_code AS STRING) AS variant_tax_code,
    CAST(cost_per_item AS STRING) AS cost_per_item,
    CAST(status AS STRING) AS status,
    'csv_current_raw' AS _hybrid_source,
    0 AS source_rank
  FROM `mischief-made-analytics.raw.shopify_products`

  UNION ALL

  SELECT
    CAST(handle AS STRING) AS handle,
    CAST(title AS STRING) AS title,
    CAST(body_html AS STRING) AS body_html,
    CAST(vendor AS STRING) AS vendor,
    CAST(product_category AS STRING) AS product_category,
    CAST(type AS STRING) AS type,
    CAST(tags AS STRING) AS tags,
    CAST(published AS STRING) AS published,
    CAST(option1_name AS STRING) AS option1_name,
    CAST(option1_value AS STRING) AS option1_value,
    CAST(option1_linked_to AS STRING) AS option1_linked_to,
    CAST(option2_name AS STRING) AS option2_name,
    CAST(option2_value AS STRING) AS option2_value,
    CAST(option2_linked_to AS STRING) AS option2_linked_to,
    CAST(option3_name AS STRING) AS option3_name,
    CAST(option3_value AS STRING) AS option3_value,
    CAST(option3_linked_to AS STRING) AS option3_linked_to,
    CAST(variant_sku AS STRING) AS variant_sku,
    CAST(variant_grams AS STRING) AS variant_grams,
    CAST(variant_inventory_tracker AS STRING) AS variant_inventory_tracker,
    CAST(variant_inventory_qty AS STRING) AS variant_inventory_qty,
    CAST(variant_inventory_policy AS STRING) AS variant_inventory_policy,
    CAST(variant_fulfillment_service AS STRING) AS variant_fulfillment_service,
    CAST(variant_price AS STRING) AS variant_price,
    CAST(variant_compare_at_price AS STRING) AS variant_compare_at_price,
    CAST(variant_requires_shipping AS STRING) AS variant_requires_shipping,
    CAST(variant_taxable AS STRING) AS variant_taxable,
    CAST(unit_price_total_measure AS STRING) AS unit_price_total_measure,
    CAST(unit_price_total_measure_unit AS STRING) AS unit_price_total_measure_unit,
    CAST(unit_price_base_measure AS STRING) AS unit_price_base_measure,
    CAST(unit_price_base_measure_unit AS STRING) AS unit_price_base_measure_unit,
    CAST(variant_barcode AS STRING) AS variant_barcode,
    CAST(image_src AS STRING) AS image_src,
    CAST(image_position AS STRING) AS image_position,
    CAST(image_alt_text AS STRING) AS image_alt_text,
    CAST(gift_card AS STRING) AS gift_card,
    CAST(seo_title AS STRING) AS seo_title,
    CAST(seo_description AS STRING) AS seo_description,
    CAST(product_rating_count AS STRING) AS product_rating_count,
    CAST(activewear_clothing_features AS STRING) AS activewear_clothing_features,
    CAST(activity AS STRING) AS activity,
    CAST(age_group AS STRING) AS age_group,
    CAST(closure_type AS STRING) AS closure_type,
    CAST(color AS STRING) AS color,
    CAST(decoration_material AS STRING) AS decoration_material,
    CAST(fabric AS STRING) AS fabric,
    CAST(footwear_material AS STRING) AS footwear_material,
    CAST(heel_height_type AS STRING) AS heel_height_type,
    CAST(occasion_style AS STRING) AS occasion_style,
    CAST(pants_length_type AS STRING) AS pants_length_type,
    CAST(sandal_style AS STRING) AS sandal_style,
    CAST(shoe_features AS STRING) AS shoe_features,
    CAST(shoe_size AS STRING) AS shoe_size,
    CAST(size AS STRING) AS size,
    CAST(target_gender AS STRING) AS target_gender,
    CAST(toe_style AS STRING) AS toe_style,
    CAST(waist_rise AS STRING) AS waist_rise,
    CAST(variant_image AS STRING) AS variant_image,
    CAST(variant_weight_unit AS STRING) AS variant_weight_unit,
    CAST(variant_tax_code AS STRING) AS variant_tax_code,
    CAST(cost_per_item AS STRING) AS cost_per_item,
    CAST(status AS STRING) AS status,
    'api_raw_candidate' AS _hybrid_source,
    1 AS source_rank
  FROM `mischief-made-analytics.raw_load.shopify_products_api_raw_candidate`
),

keyed AS (
  SELECT
    *,
    CASE
      WHEN NULLIF(LOWER(TRIM(variant_sku)), '') IS NOT NULL THEN
        CONCAT('sku::', LOWER(TRIM(variant_sku)))
      WHEN NULLIF(LOWER(TRIM(handle)), '') IS NOT NULL THEN
        CONCAT(
          'handle_options::',
          LOWER(TRIM(handle)),
          '||',
          COALESCE(LOWER(TRIM(option1_value)), ''),
          '||',
          COALESCE(LOWER(TRIM(option2_value)), ''),
          '||',
          COALESCE(LOWER(TRIM(option3_value)), '')
        )
      ELSE
        CONCAT(
          'handle_title::',
          COALESCE(LOWER(TRIM(handle)), ''),
          '||',
          COALESCE(LOWER(TRIM(title)), '')
        )
    END AS dedupe_key
  FROM combined
),

deduped AS (
  SELECT * EXCEPT(source_rank, dedupe_key)
  FROM keyed
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY dedupe_key
    ORDER BY source_rank DESC
  ) = 1
)

SELECT *
FROM deduped;