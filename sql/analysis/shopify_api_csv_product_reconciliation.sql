-- sql/analysis/shopify_api_csv_product_reconciliation.sql
-- Purpose:
-- Reconcile Shopify API product/variant landing data against the existing
-- CSV-derived product warehouse shape.
--
-- Grain:
-- One row per Shopify API product variant.
--
-- Notes:
-- - This is comparison-only.
-- - This does not modify canonical raw tables.
-- - This does not replace the CSV ingestion path.
-- - This does not change staging, marts, or business-facing analysis logic.

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_shopify_api_csv_product_reconciliation` AS

WITH
  api_products AS (
    SELECT
      shopify_product_graphql_id,
      legacy_resource_id AS api_product_legacy_resource_id,
      LOWER(TRIM(handle)) AS normalized_handle,
      handle AS api_handle,
      title AS api_product_title,
      product_type AS api_product_type,
      status AS api_product_status,
      created_at AS api_product_created_at,
      updated_at AS api_product_updated_at
    FROM `mischief-made-analytics.raw_load.shopify_products_api_latest`
  ),

  api_variants AS (
    SELECT
      shopify_product_variant_graphql_id,
      shopify_product_graphql_id,
      legacy_resource_id AS api_variant_legacy_resource_id,
      NULLIF(LOWER(TRIM(sku)), '') AS normalized_sku,
      sku AS api_variant_sku,
      title AS api_variant_title,
      barcode AS api_variant_barcode,
      SAFE_CAST(NULLIF(TRIM(price), '') AS NUMERIC) AS api_variant_price,
      SAFE_CAST(NULLIF(TRIM(compare_at_price), '') AS NUMERIC) AS api_variant_compare_at_price,
      taxable AS api_variant_taxable,
      inventory_quantity AS api_variant_inventory_quantity
    FROM `mischief-made-analytics.raw_load.shopify_product_variants_api_latest`
  ),

  api_joined AS (
    SELECT
      variants.shopify_product_variant_graphql_id,
      variants.shopify_product_graphql_id,
      products.api_product_legacy_resource_id,
      variants.api_variant_legacy_resource_id,
      products.api_handle,
      products.normalized_handle,
      products.api_product_title,
      products.api_product_type,
      products.api_product_status,
      products.api_product_created_at,
      products.api_product_updated_at,
      variants.normalized_sku,
      variants.api_variant_sku,
      variants.api_variant_title,
      variants.api_variant_barcode,
      variants.api_variant_price,
      variants.api_variant_compare_at_price,
      variants.api_variant_taxable,
      variants.api_variant_inventory_quantity
    FROM api_variants AS variants
    LEFT JOIN api_products AS products
      ON variants.shopify_product_graphql_id = products.shopify_product_graphql_id
  ),

  csv_raw_products_by_sku AS (
    SELECT
      NULLIF(LOWER(TRIM(variant_sku)), '') AS normalized_sku,
      COUNT(*) AS csv_raw_rows_for_sku,
      COUNT(DISTINCT LOWER(TRIM(handle))) AS csv_raw_distinct_handles_for_sku,
      ANY_VALUE(handle) AS csv_raw_handle_sample,
      ANY_VALUE(title) AS csv_raw_title_sample,
      ANY_VALUE(type) AS csv_raw_type_sample,
      ANY_VALUE(status) AS csv_raw_status_sample,
      SAFE_CAST(NULLIF(TRIM(ANY_VALUE(variant_price)), '') AS NUMERIC) AS csv_raw_variant_price_sample,
      SAFE_CAST(NULLIF(TRIM(ANY_VALUE(variant_compare_at_price)), '') AS NUMERIC) AS csv_raw_variant_compare_at_price_sample,
      SAFE_CAST(NULLIF(TRIM(ANY_VALUE(variant_inventory_qty)), '') AS INT64) AS csv_raw_variant_inventory_quantity_sample,
      ANY_VALUE(variant_taxable) AS csv_raw_variant_taxable_sample
    FROM `mischief-made-analytics.raw.shopify_products`
    WHERE NULLIF(LOWER(TRIM(variant_sku)), '') IS NOT NULL
    GROUP BY normalized_sku
  ),

  staging_products_by_sku AS (
    SELECT
      NULLIF(LOWER(TRIM(sku)), '') AS normalized_sku,
      COUNT(*) AS staging_rows_for_sku,
      COUNT(DISTINCT LOWER(TRIM(handle))) AS staging_distinct_handles_for_sku,
      ANY_VALUE(handle) AS staging_handle_sample,
      ANY_VALUE(title) AS staging_title_sample,
      ANY_VALUE(type) AS staging_type_sample,
      ANY_VALUE(status) AS staging_status_sample,
      ANY_VALUE(price) AS staging_price_sample,
      ANY_VALUE(compare_at_price) AS staging_compare_at_price_sample,
      ANY_VALUE(inventory_quantity) AS staging_inventory_quantity_sample,
      ANY_VALUE(variant_taxable) AS staging_variant_taxable_sample
    FROM `mischief-made-analytics.staging.stg_shopify_products`
    WHERE NULLIF(LOWER(TRIM(sku)), '') IS NOT NULL
    GROUP BY normalized_sku
  ),

  dim_products_by_sku AS (
    SELECT
      NULLIF(LOWER(TRIM(sku)), '') AS normalized_sku,
      COUNT(*) AS dim_rows_for_sku,
      ANY_VALUE(handle) AS dim_handle_sample,
      ANY_VALUE(title) AS dim_title_sample,
      ANY_VALUE(type) AS dim_type_sample,
      ANY_VALUE(status) AS dim_status_sample,
      ANY_VALUE(price) AS dim_price_sample,
      ANY_VALUE(compare_at_price) AS dim_compare_at_price_sample,
      ANY_VALUE(inventory_quantity) AS dim_inventory_quantity_sample,
      ANY_VALUE(variant_taxable) AS dim_variant_taxable_sample
    FROM `mischief-made-analytics.marts.dim_products`
    WHERE NULLIF(LOWER(TRIM(sku)), '') IS NOT NULL
    GROUP BY normalized_sku
  )

SELECT
  api.shopify_product_variant_graphql_id,
  api.shopify_product_graphql_id,
  api.api_product_legacy_resource_id,
  api.api_variant_legacy_resource_id,

  api.api_handle,
  api.api_product_title,
  api.api_product_type,
  api.api_product_status,
  api.api_product_created_at,
  api.api_product_updated_at,

  api.api_variant_sku,
  api.normalized_sku,
  api.api_variant_title,
  api.api_variant_barcode,
  api.api_variant_price,
  api.api_variant_compare_at_price,
  api.api_variant_taxable,
  api.api_variant_inventory_quantity,

  raw.csv_raw_rows_for_sku,
  raw.csv_raw_distinct_handles_for_sku,
  raw.csv_raw_handle_sample,
  raw.csv_raw_title_sample,
  raw.csv_raw_type_sample,
  raw.csv_raw_status_sample,
  raw.csv_raw_variant_price_sample,
  raw.csv_raw_variant_compare_at_price_sample,
  raw.csv_raw_variant_inventory_quantity_sample,
  raw.csv_raw_variant_taxable_sample,

  staging.staging_rows_for_sku,
  staging.staging_distinct_handles_for_sku,
  staging.staging_handle_sample,
  staging.staging_title_sample,
  staging.staging_type_sample,
  staging.staging_status_sample,
  staging.staging_price_sample,
  staging.staging_compare_at_price_sample,
  staging.staging_inventory_quantity_sample,
  staging.staging_variant_taxable_sample,

  dim.dim_rows_for_sku,
  dim.dim_handle_sample,
  dim.dim_title_sample,
  dim.dim_type_sample,
  dim.dim_status_sample,
  dim.dim_price_sample,
  dim.dim_compare_at_price_sample,
  dim.dim_inventory_quantity_sample,
  dim.dim_variant_taxable_sample,

  CASE
    WHEN api.normalized_sku IS NULL THEN 'api_variant_missing_sku'
    WHEN raw.normalized_sku IS NOT NULL
      AND staging.normalized_sku IS NOT NULL
      AND dim.normalized_sku IS NOT NULL
      THEN 'matched_api_csv_staging_dim'
    WHEN raw.normalized_sku IS NOT NULL
      AND staging.normalized_sku IS NOT NULL
      AND dim.normalized_sku IS NULL
      THEN 'matched_api_csv_staging_missing_dim'
    WHEN raw.normalized_sku IS NOT NULL
      AND staging.normalized_sku IS NULL
      AND dim.normalized_sku IS NULL
      THEN 'matched_api_csv_only'
    WHEN raw.normalized_sku IS NULL
      AND staging.normalized_sku IS NULL
      AND dim.normalized_sku IS NULL
      THEN 'api_only'
    ELSE 'partial_match_other'
  END AS reconciliation_status,

  CASE
    WHEN api.api_variant_price IS NULL THEN 'missing_api_price'
    WHEN staging.staging_price_sample IS NULL THEN 'missing_staging_price'
    WHEN api.api_variant_price = staging.staging_price_sample THEN 'price_matches_staging'
    ELSE 'price_differs_from_staging'
  END AS price_reconciliation_status,

  ROUND(api.api_variant_price - staging.staging_price_sample, 2) AS api_vs_staging_price_diff,

  CASE
    WHEN api.api_variant_inventory_quantity IS NULL THEN 'missing_api_inventory'
    WHEN staging.staging_inventory_quantity_sample IS NULL THEN 'missing_staging_inventory'
    WHEN api.api_variant_inventory_quantity = staging.staging_inventory_quantity_sample THEN 'inventory_matches_staging'
    ELSE 'inventory_differs_from_staging'
  END AS inventory_reconciliation_status,

  api.api_variant_inventory_quantity - staging.staging_inventory_quantity_sample AS api_vs_staging_inventory_diff

FROM api_joined AS api
LEFT JOIN csv_raw_products_by_sku AS raw
  ON api.normalized_sku = raw.normalized_sku
LEFT JOIN staging_products_by_sku AS staging
  ON api.normalized_sku = staging.normalized_sku
LEFT JOIN dim_products_by_sku AS dim
  ON api.normalized_sku = dim.normalized_sku;