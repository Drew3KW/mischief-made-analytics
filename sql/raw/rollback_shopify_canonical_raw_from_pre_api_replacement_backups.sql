-- File: sql/raw/rollback_shopify_canonical_raw_from_pre_api_replacement_backups.sql
-- Purpose:
-- Restore production Shopify canonical raw tables from the pre-API-replacement
-- backups created at the start of Milestone 41.
--
-- Important notes:
-- - Do not run this unless the replacement needs to be rolled back.
-- - After rollback, rerun the standard warehouse refresh so staging, marts,
--   analysis, and validation reflect the restored canonical raw tables.

CREATE OR REPLACE TABLE `mischief-made-analytics.raw.shopify_products` AS
SELECT *
FROM `mischief-made-analytics.raw_load.shopify_products_pre_api_replacement_backup_20260512`;

CREATE OR REPLACE TABLE `mischief-made-analytics.raw.shopify_customers` AS
SELECT *
FROM `mischief-made-analytics.raw_load.shopify_customers_pre_api_replacement_backup_20260512`;

CREATE OR REPLACE TABLE `mischief-made-analytics.raw.shopify_orders` AS
SELECT *
FROM `mischief-made-analytics.raw_load.shopify_orders_pre_api_replacement_backup_20260512`;