-- sql/marts/dim_product_families.sql
-- Model: marts.dim_product_families
-- Grain: one row per product_family_key
-- Purpose: reusable product-family dimension for downstream family-level analysis
--
-- Notes:
-- - Built from marts.product_family_map
-- - Canonical family name is selected in product_family_map and reused here
-- - Includes lightweight descriptive metadata for downstream reporting

CREATE OR REPLACE TABLE `mischief-made-analytics.marts.dim_product_families` AS

SELECT
    product_family_key,
    ANY_VALUE(canonical_product_family_name) AS product_family_name,
    COUNT(*) AS products_in_family,
    COUNT(DISTINCT source_type) AS source_types_in_family,
    COUNTIF(source_type = 'catalog') AS catalog_products_in_family,
    COUNTIF(source_type = 'order_only_sku') AS order_only_sku_products_in_family,
    COUNTIF(source_type = 'order_only_name') AS order_only_name_products_in_family
FROM `mischief-made-analytics.marts.product_family_map`
GROUP BY product_family_key;
