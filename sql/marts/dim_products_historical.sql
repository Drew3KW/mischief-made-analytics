-- Model: marts.dim_products_historical
-- Grain: one row per product_key
-- Purpose: historical product dimension for complete sold-item coverage
-- Notes:
--   - product_key = SKU|normalized_sku when SKU exists
--   - product_key = NAME|normalized_product_name otherwise
--   - Unifies current catalog products, deleted historical products, and blank-SKU sold items

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.dim_products_historical` AS

WITH catalog_products AS (
  SELECT
    CONCAT('SKU|', LOWER(TRIM(sku))) AS product_key,
    LOWER(TRIM(sku)) AS normalized_sku,
    CAST(NULL AS STRING) AS normalized_product_name,
    sku,
    title AS product_name,
    handle,
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
    status,
    TRUE AS in_catalog_export,
    FALSE AS seen_in_orders,
    'catalog' AS source_type
  FROM `mischief-made-analytics.marts.dim_products`
),

order_products AS (
  SELECT
    CASE
      WHEN sku IS NOT NULL AND TRIM(sku) <> ''
        THEN CONCAT('SKU|', LOWER(TRIM(sku)))
      ELSE CONCAT('NAME|', LOWER(TRIM(product_name)))
    END AS product_key,
    CASE
      WHEN sku IS NOT NULL AND TRIM(sku) <> ''
        THEN LOWER(TRIM(sku))
      ELSE CAST(NULL AS STRING)
    END AS normalized_sku,
    CASE
      WHEN sku IS NULL OR TRIM(sku) = ''
        THEN LOWER(TRIM(product_name))
      ELSE CAST(NULL AS STRING)
    END AS normalized_product_name,
    sku,
    product_name,
    CAST(NULL AS STRING) AS handle,
    CAST(NULL AS STRING) AS body_html,
    vendor,
    CAST(NULL AS STRING) AS product_category,
    CAST(NULL AS STRING) AS type,
    tags,
    CAST(NULL AS STRING) AS published,
    CAST(NULL AS STRING) AS option1_name,
    CAST(NULL AS STRING) AS option1_value,
    CAST(NULL AS STRING) AS option2_name,
    CAST(NULL AS STRING) AS option2_value,
    CAST(NULL AS STRING) AS option3_name,
    CAST(NULL AS STRING) AS option3_value,
    CAST(NULL AS NUMERIC) AS price,
    CAST(NULL AS NUMERIC) AS compare_at_price,
    CAST(NULL AS INT64) AS inventory_quantity,
    CAST(NULL AS INT64) AS weight_grams,
    CAST(NULL AS STRING) AS variant_inventory_tracker,
    CAST(NULL AS STRING) AS variant_inventory_policy,
    CAST(NULL AS STRING) AS variant_fulfillment_service,
    CAST(NULL AS STRING) AS variant_requires_shipping,
    CAST(NULL AS STRING) AS variant_taxable,
    CAST(NULL AS STRING) AS image_src,
    CAST(NULL AS INT64) AS image_position,
    CAST(NULL AS STRING) AS image_alt_text,
    CAST(NULL AS STRING) AS variant_barcode,
    CAST(NULL AS STRING) AS variant_image,
    CAST(NULL AS STRING) AS variant_weight_unit,
    CAST(NULL AS NUMERIC) AS cost_per_item,
    CAST(NULL AS STRING) AS status,
    FALSE AS in_catalog_export,
    TRUE AS seen_in_orders,
    CASE
      WHEN sku IS NOT NULL AND TRIM(sku) <> '' THEN 'order_only_sku'
      ELSE 'order_only_name'
    END AS source_type
  FROM (
    SELECT
      sku,
      product_name,
      vendor,
      tags,
      ROW_NUMBER() OVER (
        PARTITION BY
          CASE
            WHEN sku IS NOT NULL AND TRIM(sku) <> ''
              THEN CONCAT('SKU|', LOWER(TRIM(sku)))
            ELSE CONCAT('NAME|', LOWER(TRIM(product_name)))
          END
        ORDER BY created_at_ts DESC
      ) AS row_num
    FROM `mischief-made-analytics.staging.stg_shopify_order_items`
    WHERE (sku IS NOT NULL AND TRIM(sku) <> '')
       OR (product_name IS NOT NULL AND TRIM(product_name) <> '')
  )
  WHERE row_num = 1
),

combined AS (
  SELECT * FROM catalog_products
  UNION ALL
  SELECT * FROM order_products
),

ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY product_key
      ORDER BY
        CASE WHEN in_catalog_export THEN 1 ELSE 2 END,
        CASE WHEN product_name IS NOT NULL AND TRIM(product_name) <> '' THEN 1 ELSE 2 END,
        CASE WHEN vendor IS NOT NULL AND TRIM(vendor) <> '' THEN 1 ELSE 2 END
    ) AS row_num,
    MAX(CASE WHEN in_catalog_export THEN 1 ELSE 0 END) OVER (PARTITION BY product_key) = 1 AS any_catalog_match,
    MAX(CASE WHEN seen_in_orders THEN 1 ELSE 0 END) OVER (PARTITION BY product_key) = 1 AS any_order_match
  FROM combined
)

SELECT
  product_key,
  normalized_sku,
  normalized_product_name,
  sku,
  product_name,
  handle,
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
  status,
  any_catalog_match AS in_catalog_export,
  any_order_match AS seen_in_orders,
  source_type
FROM ranked
WHERE row_num = 1;
