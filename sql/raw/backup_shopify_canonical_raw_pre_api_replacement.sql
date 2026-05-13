-- File: sql/raw/backup_shopify_canonical_raw_pre_api_replacement.sql
-- Purpose:
-- Create backup copies of the current production Shopify canonical raw tables
-- before the first API-backed canonical raw replacement MVP.
--
-- Important notes:
-- - Run this before replacing raw.shopify_products, raw.shopify_customers,
--   or raw.shopify_orders.
-- - These are normal backup tables in raw_load so they can be queried and
--   restored with simple CREATE OR REPLACE TABLE statements.
-- - Do not rerun this after replacement unless you intentionally want to
--   overwrite the pre-replacement backups.

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.shopify_products_pre_api_replacement_backup_20260512` AS
SELECT *
FROM `mischief-made-analytics.raw.shopify_products`;

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.shopify_customers_pre_api_replacement_backup_20260512` AS
SELECT *
FROM `mischief-made-analytics.raw.shopify_customers`;

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.shopify_orders_pre_api_replacement_backup_20260512` AS
SELECT *
FROM `mischief-made-analytics.raw.shopify_orders`;